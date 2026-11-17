#!/usr/bin/env python3
"""Discrete-event model of 1s dispatch ticks, oldest-due fairness and per-page service.
No network calls. This is a capacity model, not a 10k-account application load test.
"""
import heapq, json, math, statistics
from collections import deque
from pathlib import Path

def percentile(values, p):
    if not values: return None
    values.sort(); return values[min(len(values)-1, int((len(values)-1)*p))]

def simulate(count, duration=43200, faults=False, initial_backlog_days=0):
    accounts=[]
    for i in range(count):
        active=i%10==0; period=180 if active else (3600 if i%10==1 else None)
        accounts.append(dict(id=i, active=active, period=period, offset=i%179,
          delay=(i%4)*90, due=0, lease=0, interval=45, remaining=0, last_seen=-1,
          requests=0, polls=0, started=None, through=-initial_backlog_days*86400, failures=0))
    jobs=[]; next_request=0; served=0; lags=[]; max_backlog=0; throttle=0; restarts=0
    sleeping=[]; ready=[]
    def reschedule(a, earliest=None):
        a['generation']=a.get('generation',0)+1
        heapq.heappush(sleeping,(max(a['due'],a['lease']) if earliest is None else earliest,a['due'],a['id'],a['generation']))
    for a in accounts:reschedule(a)
    for now in range(duration):
        if faults and now==21600:
            jobs=[]; restarts+=1 # committed account/run state survives; dispatch leases expire.
        while sleeping and sleeping[0][0]<=now:
            _,due,i,generation=heapq.heappop(sleeping)
            if accounts[i]['generation']==generation:heapq.heappush(ready,(due,i,generation))
        max_backlog=max(max_backlog,len(ready))
        while ready:
            _,i,generation=heapq.heappop(ready);a=accounts[i]
            if generation!=a['generation']:continue
            a['lease']=now+30;reschedule(a,now+30)
            heapq.heappush(jobs,(now,i));break
        if jobs and jobs[0][0]<=now:
            _,i=heapq.heappop(jobs); a=accounts[i]
            if now<next_request:
                a['lease']=next_request;reschedule(a);continue
            served+=1; a['requests']+=1;next_request=now+1
            if faults and (3600<=now<4200 or served%997==0):
                a['failures']+=1; a['due']=now+min(21600,30*2**min(a['failures']-1,9))+i%11;a['lease']=0
                if served%997==0:next_request=now+60;throttle+=1
                reschedule(a);continue
            if a['remaining']==0:
                a['started']=now;a['upper']=min(now-5,a['through']-172800+604800)
                # Full 48-hour lookback plus any outage backlog; empty polls use one request.
                width=172800+max(0,a['upper']-a['through'])
                events=math.ceil(width/a['period']) if a['period'] else 0
                a['remaining']=max(1,2*math.ceil(events/200))
            a['remaining']-=1;a['lease']=0;a['failures']=0
            if a['remaining']:
                a['due']=now+1;reschedule(a)
                continue
            previous=a['through'];a['through']=a['upper'];a['polls']+=1
            inserted=0
            if a['period']:
                newest=math.floor((a['upper']-a['delay']-a['offset'])/a['period'])
                for index in range(max(0,a['last_seen']+1),newest+1):
                    timestamp=a['offset']+index*a['period']
                    if timestamp>=previous-172800:
                        lags.append(now-timestamp);inserted+=1
                a['last_seen']=max(newest,a['last_seen'])
            recent=bool(a['period'] and a['last_seen']>=0 and now-(a['offset']+a['last_seen']*a['period'])<=1800)
            active=bool(inserted or recent)
            a['interval']=max(45 if active else min(3600,a['interval']*2),count*3*(1 if active else 2))
            a['due']=now+a['interval'];reschedule(a)
    missed=0
    for a in accounts:
        if a['period']:
            expected=max(-1,math.floor((duration-a['delay']-a['offset'])/a['period']))
            missed+=max(0,expected-a['last_seen'])
    return dict(accounts=count, associated_users=count*2, associations_per_account=2, distinct_source_schedules=count, hours=duration/3600, faults=faults, initial_backlog_days=initial_backlog_days, budget_requests_per_second=1,
      simulated_requests=served, effective_requests_per_second=served/duration,
      active_fraction=0.1, occasional_fraction=0.1, inactive_fraction=0.8, active_events_per_hour=20,
      overlapping_lookback_hours=48, request_latency_model_seconds=0.2,
      backlog_max_accounts=max_backlog, polls_completed=sum(a['polls'] for a in accounts),
      accounts_never_polled=sum(a['polls']==0 for a in accounts), requests_min=min(a['requests'] for a in accounts),
      requests_max=max(a['requests'] for a in accounts), observed_new_events=len(lags), pending_visible_events=missed,
      observed_event_lag_p50_seconds=percentile(lags,.5), observed_event_lag_p95_seconds=percentile(lags,.95),
      maximum_since_success_seconds=max(duration-a['through'] for a in accounts),
      throttling_cooldowns=throttle, process_restarts=restarts,
      warning='Lag percentiles describe committed simulated events; pending events are reported separately. This model excludes database/queue overhead and is not a throughput guarantee.')

if __name__=='__main__':
    results=[simulate(n,faults=faults) for n in (1,100,1000,10000) for faults in (False,True)]
    results += [simulate(1000, duration=172800, faults=True, initial_backlog_days=14)]
    print(json.dumps({'model':'one-second dispatcher-v2','results':results},indent=2))
