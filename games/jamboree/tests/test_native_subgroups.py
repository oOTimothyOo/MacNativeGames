"""Vertex input lowering preserves real subgroup execution, without game content."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from test_subgroup_masks import vertex, instructions

TOOLS = Path(__file__).resolve().parents[1] / 'runtime/gfx/tools'
sys.path.insert(0, str(TOOLS))
import dmsh_subgroups


class NativeSubgroupTests(unittest.TestCase):
    def test_only_interface_changes(self):
        with tempfile.TemporaryDirectory() as work:
            path = Path(work) / 'vertex.spv'
            original = vertex()
            path.write_bytes(original)
            self.assertTrue(dmsh_subgroups.rewrite(path))
            body = lambda data: [x for x in instructions(data) if x[0] & 65535 not in (5, 71)]
            self.assertEqual(body(original), body(path.read_bytes()))

    def test_other_masks_are_left_unchanged(self):
        for mask in (4416, 4417, 4418, 4419):
            with self.subTest(mask=mask), tempfile.TemporaryDirectory() as work:
                path = Path(work) / 'vertex.spv'
                original = vertex(mask=mask)
                path.write_bytes(original)
                self.assertFalse(dmsh_subgroups.rewrite(path))
                self.assertEqual(original, path.read_bytes())

    def test_reserved_input_names_are_rejected(self):
        with tempfile.TemporaryDirectory() as work:
            path = Path(work) / 'vertex.spv'
            path.write_bytes(vertex())
            self.assertTrue(dmsh_subgroups.rewrite(path))
            original = path.read_bytes()
            self.assertFalse(dmsh_subgroups.rewrite(path))
            self.assertEqual(original, path.read_bytes())

    def test_helper_reference_arguments_keep_local_storage(self):
        source = '''
struct main0_in { uint dm_native_sg_lane [[attribute(31)]];
uint4 dm_native_sg_lt [[attribute(30)]];
};
struct main0_out { float4 p [[position]]; };
uint shared(thread uint& dm_native_sg_lane) { return dm_native_sg_lane; }
vertex main0_out main0(main0_in in [[stage_in]], uint v [[vertex_id]]) {
uint l=shared(in.dm_native_sg_lane); main0_out out;
out.p=float4(l+in.dm_native_sg_lt.x); return out;
}
'''
        # Match SPIRV-Cross's one-member-per-line interface declarations.
        source = source.replace('struct main0_in { ', 'struct main0_in {\n')
        result = dmsh_subgroups.metal(source)
        self.assertNotIn('[[stage_in]]', result)
        self.assertNotIn('[[attribute(', result)
        self.assertIn('shared(dm_native_sg_lane)', result)
        self.assertIn('uint dm_native_sg_lane = dm_native_lane_id();', result)
        self.assertIn('uint4 dm_native_sg_lt = dm_native_lt_mask();', result)

    @unittest.skipUnless(shutil.which('spirv-cross'), 'SPIRV-Cross is not installed')
    def test_spirv_cross_output_has_no_synthetic_attributes(self):
        with tempfile.TemporaryDirectory() as work:
            path = Path(work) / 'vertex.spv'
            path.write_bytes(vertex())
            self.assertTrue(dmsh_subgroups.rewrite(path))
            result = subprocess.run(['spirv-cross', str(path), '--msl', '--msl-version', '20300'], capture_output=True, text=True)
            self.assertEqual(0, result.returncode, result.stderr)
            source = dmsh_subgroups.metal(result.stdout)
            self.assertNotIn('[[attribute(', source)
            self.assertIn('dm_native_lt_mask()', source)


if __name__ == '__main__':
    unittest.main()
