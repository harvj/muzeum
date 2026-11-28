import copy
import unittest

import muzeum_deploy as deploy


class SchemaPreservationTests(unittest.TestCase):
    def setUp(self):
        self.schema = {
            'tables': ['catalog_track_slots'],
            'columns': [{'column_name': 'position', 'data_type': 'integer'}],
            'constraints': [{'conname': 'fk_existing'}],
            'triggers': [{'tgname': 'existing_trigger'}],
            'indexes': [{'indexname': 'index_recording_id', 'indisvalid': True, 'indisready': True}],
        }
        self.before = {'databases': {'primary': self.schema}}
        self.after = copy.deepcopy(self.before)

    def test_additive_changes_are_allowed(self):
        self.after['databases']['primary']['tables'].append('new_table')
        deploy.verify_schema_preservation(self.before, self.after)

    def test_existing_objects_are_preserved(self):
        for kind in self.schema:
            with self.subTest(kind=kind):
                after = copy.deepcopy(self.after)
                after['databases']['primary'][kind].clear()
                with self.assertRaisesRegex(RuntimeError, rf'primary\.{kind}'):
                    deploy.verify_schema_preservation(self.before, after)

    def test_no_special_case_allows_removing_an_existing_index(self):
        self.after['databases']['primary']['indexes'][0]['indexname'] = 'replacement_index'
        with self.assertRaisesRegex(RuntimeError, 'primary.indexes'):
            deploy.verify_schema_preservation(self.before, self.after)
