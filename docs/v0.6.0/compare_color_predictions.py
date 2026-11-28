"""Compare metadata rules and exact evidence-pattern reuse on Stage A responses."""
import argparse
import json
from pathlib import Path

# These extrapolate the operator's Boards of Canada Gray reference to a
# narrow sample. They are hypotheses for the experiment, not manual decisions.
REFERENCE = {
    "2a72cd7b-f566-4c91-8e9b-7b33b95dfff7": "gray",  # Roygbiv (example)
    "a4ec6700-5ddb-4d4f-98b0-f82a480c50e0": "gray",  # Turquoise Hexagon Sun
    "e658982b-4317-4369-a6ab-e50ceb00c0e5": "gray",  # Telephasic Workshop
    "25bf43d2-5808-4039-af8a-400d19d25017": "light-green",  # Red Clay
}
EXAMPLE_ID = "2a72cd7b-f566-4c91-8e9b-7b33b95dfff7"
TERMS = {"ambient": "yellow", "ambient techno": "yellow", "idm": "gray",
         "electro": "gray", "new wave": "gray", "jazz": "light-green"}
UNINFORMATIVE = {"electronic", "electronica"}


def features(recording):
    return {tag["name"].casefold() for tag in recording.get("genres", [])} - UNINFORMATIVE


def metadata_prediction(terms):
    supported = {TERMS[term] for term in terms if term in TERMS}
    return next(iter(supported)) if len(supported) == 1 else None


def evaluate(directory):
    recordings = {}
    for path in sorted(directory.glob("recording-*.json")):
        row = json.loads(path.read_text())
        if "id" in row:
            recordings[row["id"]] = row
    example = features(recordings[EXAMPLE_ID])
    holdout = {identity: color for identity, color in REFERENCE.items() if identity != EXAMPLE_ID}
    for identity, expected in holdout.items():
        row = recordings[identity]
        terms = features(row)
        metadata = metadata_prediction(terms)
        # One example cannot establish how far a pattern generalizes. This
        # deliberately narrow trial requires exact overlap of mapped features.
        support = terms & TERMS.keys()
        analog = REFERENCE[EXAMPLE_ID] if support and support == example & TERMS.keys() else None
        print(f"{row['title']} | expected {expected} | metadata {metadata or 'abstain'} | analog {analog or 'abstain'}")
    labeled_evidence = sum(bool(row.get("genres") or row.get("tags")) for row in recordings.values())
    print(f"Recording-scope metadata present on {labeled_evidence}/{len(recordings)} sampled recordings")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage_a_snapshot", type=Path)
    evaluate(parser.parse_args().stage_a_snapshot)
