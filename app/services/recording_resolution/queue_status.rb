module RecordingResolution
  class QueueStatus
    attr_reader :state, :phase, :worker, :ahead, :waiting_seconds, :scheduled_at, :attention

    def initialize(request)
      return unless request.active?
      if request.state == "refreshing" && request.lease_until&.future?
        @state = :investigating
        return
      end
      return unless CanonicalCatalogJob.queue_adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter)

      @now = Time.current
      @queue = CanonicalCatalogJob.queue_name
      jobs = SolidQueue::Job.where(queue_name: @queue, finished_at: nil, class_name: CanonicalCatalogJob.name)
        .where("arguments::jsonb -> 'arguments' -> 0 = CAST(? AS jsonb)", request.id.to_s)
      ready = executions(SolidQueue::ReadyExecution, jobs).order(:priority, :job_id).first
      blocked = executions(SolidQueue::BlockedExecution, jobs).order(:created_at).first
      scheduled = executions(SolidQueue::ScheduledExecution, jobs).order(:scheduled_at).first
      claimed = executions(SolidQueue::ClaimedExecution, jobs).order(:created_at).first if request.state == "pending"
      execution = ready || claimed || blocked || scheduled
      return unless execution

      @state = :queued
      @phase = if ready
        :ready
      elsif claimed
        :claimed
      elsif blocked
        :blocked
      elsif scheduled.scheduled_at > @now
        @scheduled_at = scheduled.scheduled_at
        @state = :retrying
        :scheduled
      else
        :dispatching
      end
      since = phase == :dispatching ? scheduled.scheduled_at : execution.created_at
      @waiting_seconds = [ (@now - since).floor, 0 ].max
      if phase == :claimed
        @worker = :assigned
      else
        inspect_workers(ready)
      end
      inspect_delay
    rescue ActiveRecord::ActiveRecordError => error
      Rails.logger.warn("Investigation queue lookup failed for #{request.id}: #{error.class}")
      @state = :unavailable
    end

    private

    def executions(model, jobs)
      model.where(job_id: jobs.select(:id))
    end

    def live_processes(kind)
      SolidQueue::Process.where(kind:).where("last_heartbeat_at > ?", @now - SolidQueue.process_alive_threshold)
    end

    def inspect_workers(ready)
      @paused = SolidQueue::Pause.exists?(queue_name: @queue)
      processes = live_processes("Worker").to_a
      selectors = processes.to_h { |process| [ process.id, process.metadata["queues"].presence&.split(",")&.map(&:strip) ] }
      eligible = processes.select do |process|
        Array(selectors[process.id]).any? { |name| name.end_with?("*") ? @queue.start_with?(name.delete_suffix("*")) : name == @queue }
      end
      unknown = selectors.values.any?(&:nil?)
      claims = SolidQueue::ClaimedExecution.where(process_id: eligible.map(&:id)).group(:process_id).count
      @worker = if @paused
        :paused
      elsif eligible.empty?
        unknown ? :unknown : :unavailable
      elsif eligible.any? { |process| capacity(process).to_i > claims.fetch(process.id, 0) }
        :available
      elsif unknown || eligible.any? { |process| !capacity(process)&.positive? }
        :unknown
      else
        :busy
      end

      orders = eligible.map { |process| selectors.fetch(process.id) }.uniq
      if ready && !@paused && !unknown && orders.one? && orders.first.none? { |name| name.include?("*") }
        higher = orders.first.take_while { |name| name != @queue } - SolidQueue::Pause.pluck(:queue_name)
        @ahead = SolidQueue::ReadyExecution.where(queue_name: higher).count +
          SolidQueue::ReadyExecution.where(queue_name: @queue)
            .where("(priority, job_id) < (?, ?)", ready.priority, ready.job_id).count
      end
      @longest_worker_age = eligible.map { |process| @now - process.created_at }.max.to_i
    end

    def capacity(process)
      Integer(process.metadata["pool_size"], exception: false)
    end

    def inspect_delay
      return @attention = :paused if @paused && phase != :scheduled

      threshold = Integer(ENV.fetch("MUZEUM_INVESTIGATION_QUEUE_WAIT_SECONDS", "300"), exception: false)
      threshold = 300 unless threshold&.positive?
      return if waiting_seconds < threshold || phase.in?([ :scheduled, :claimed ])

      @attention = if phase == :dispatching
        live_processes("Dispatcher").exists? ? :dispatch_stalled : :dispatcher_unavailable
      elsif worker == :unavailable
        :worker_unavailable
      elsif phase == :blocked
        :blocked
      elsif worker == :available && ahead == 0 && @longest_worker_age >= threshold && SolidQueue.preserve_finished_jobs? &&
          !SolidQueue::Job.where(finished_at: (@now - threshold)..).exists?
        :stalled
      elsif worker != :busy
        :delayed
      end
    end
  end
end
