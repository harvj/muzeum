## Resolver

The resolver maps scrobbles to recordings via recording surfaces.

Responsibilities:
- Create surfaces for unseen presentations
- Reuse existing surfaces for repeats
- Reinforce confidence via observation frequency
- Assign provisional recordings

The resolver **does not**:
- Perform fuzzy matching
- Strip parentheticals
- Trust upstream MBIDs
- Decide canonical truth

### Learning Model

Learning occurs by:
- Repeated surface observation
- Increasing surface confidence
- Stable mapping to a recording hypothesis
