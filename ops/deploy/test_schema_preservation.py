import copy
from pathlib import Path
import tempfile
import unittest

import muzeum_deploy as deploy


class SchemaPreservationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.release = Path(temporary.name)
        project = Path(__file__).resolve().parents[2]
        for path in (deploy.EDITION_SLOT_MIGRATION['path'], 'config/deploy/migrations.json'):
            target = self.release / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((project / path).read_bytes())

        def index(name, definition):
            return {'indexname': name, 'indexdef': definition, 'indisvalid': True, 'indisready': True}

        schema = {
            'tables': ['catalog_track_slots'], 'columns': [{'column_name': 'position', 'data_type': 'integer'}],
            'constraints': [{'conname': 'fk_existing'}], 'triggers': [{'tgname': 'existing_trigger'}],
            'indexes': [index('index_recording_id', 'Existing definition')],
        }
        self.before = {'pending': [deploy.EDITION_SLOT_MIGRATION.copy()], 'databases': {'primary': copy.deepcopy(schema)}}
        self.before['databases']['primary']['indexes'].append(index(deploy.RETIRED_SLOT_INDEX, deploy.RETIRED_SLOT_DEFINITION))
        self.after = {'pending': [], 'databases': {'primary': copy.deepcopy(schema)}}
        for name, definition in deploy.REPLACEMENT_SLOT_INDEXES.items():
            self.after['databases']['primary']['indexes'].append(
                index(name, f'CREATE UNIQUE INDEX {name} ON public.catalog_track_slots USING btree {definition}')
            )

    def test_exact_replacement_passes(self):
        deploy.verify_schema_preservation(self.release, self.before, self.after)

    def test_missing_invalid_or_changed_replacement_is_rejected(self):
        for change in ('missing', 'invalid', 'not_ready', 'definition'):
            with self.subTest(change=change):
                after = copy.deepcopy(self.after)
                indexes = after['databases']['primary']['indexes']
                if change == 'missing':
                    indexes.pop()
                elif change == 'definition':
                    indexes[-1]['indexdef'] = indexes[-1]['indexdef'].replace('UNIQUE ', '')
                else:
                    indexes[-1]['indisvalid' if change == 'invalid' else 'indisready'] = False
                with self.assertRaisesRegex(RuntimeError, 'replacement catalog index'):
                    deploy.verify_schema_preservation(self.release, self.before, after)

    def test_unrelated_schema_change_is_rejected(self):
        for kind in ('tables', 'columns', 'constraints', 'triggers', 'indexes'):
            with self.subTest(kind=kind):
                after = copy.deepcopy(self.after)
                after['databases']['primary'][kind].pop(0)
                with self.assertRaisesRegex(RuntimeError, rf'primary\.{kind}'):
                    deploy.verify_schema_preservation(self.release, self.before, after)

    def test_retired_definition_must_match(self):
        self.before['databases']['primary']['indexes'][-1]['indexdef'] += ' INCLUDE (id)'
        with self.assertRaisesRegex(RuntimeError, 'retired catalog'):
            deploy.verify_schema_preservation(self.release, self.before, self.after)

    def test_replacement_requires_the_exact_pending_migration(self):
        self.before['pending'][0]['sha256'] = '0' * 64
        with self.assertRaisesRegex(RuntimeError, 'primary.indexes'):
            deploy.verify_schema_preservation(self.release, self.before, self.after)

    def test_matching_manifest_does_not_authorize_altered_bytes(self):
        (self.release / deploy.EDITION_SLOT_MIGRATION['path']).write_text('altered')
        with self.assertRaisesRegex(RuntimeError, 'migration bytes'):
            deploy.verify_schema_preservation(self.release, self.before, self.after)
