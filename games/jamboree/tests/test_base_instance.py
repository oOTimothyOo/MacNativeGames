"""Content-free checks for indirect draws' base-instance shader lowering."""
import ast
from pathlib import Path
import re
import unittest

BUILDER = Path(__file__).resolve().parents[1] / 'runtime/gfx/tools/dmsh_build.py'


def lowering(name='vs_base_instance'):
    # Import the pure lowering without running the game-dependent build entry.
    tree = ast.parse(BUILDER.read_text())
    nodes = [n for n in tree.body if
             isinstance(n, ast.FunctionDef) and n.name in ('vs_base_instance', 'vs_depth', 'vs_tf') or
             isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'VP_BASE_INSTANCE' for t in n.targets)]
    scope = {'re': re, 'TF_SLOT': 8}
    exec(compile(ast.Module(body=nodes, type_ignores=[]), str(BUILDER), 'exec'), scope)
    return scope[name]


def fixture(existing=False):
    base = ', uint gl_BaseInstance [[base_instance]]' if existing else ''
    return '''#include <metal_stdlib>
using namespace metal;
struct C { float4 _m0[4096]; };
struct A { constant C* vp_c0 [[id(0)]]; device uint* dst [[id(1)]]; };
struct main0_out { float4 gl_Position [[position]]; };
vertex main0_out main0(constant A& spvDescriptorSet0 [[buffer(0)]], uint v [[vertex_id]], uint instance [[instance_id]]%s)
{
    main0_out out = {};
    uint relative = %s;
    uint chosen = relative + as_type<uint>((*spvDescriptorSet0.vp_c0)._m0[100].y);
    spvDescriptorSet0.dst[relative * 16u + v] = chosen;
    out.gl_Position = float4(0.0, 0.0, 0.0, 1.0);
    return out;
}
''' % (base, 'instance - gl_BaseInstance' if existing else 'instance')


class BaseInstanceTests(unittest.TestCase):
    def setUp(self):
        self.lower = lowering()

    def test_shader_without_driver_word_is_unchanged(self):
        source = fixture().replace('_m0[100].y', '_m0[100].x')
        self.assertEqual(source, self.lower(source))

    def test_adds_metal_parameter_through_buffer_attribute_parentheses(self):
        source = self.lower(fixture())
        self.assertEqual(1, source.count('[[base_instance]]'))
        self.assertNotIn('(*spvDescriptorSet0.vp_c0)._m0[100].y', source)
        self.assertIn('as_type<uint>(as_type<float>(gl_BaseInstance))', source)

    def test_reuses_existing_parameter(self):
        source = self.lower(fixture(existing=True))
        self.assertEqual(1, source.count('uint gl_BaseInstance [[base_instance]]'))
        self.assertIn('instance - gl_BaseInstance', source)

    def test_leaves_adjacent_driver_words_unchanged(self):
        source = fixture().replace('uint chosen =', 'float adjacent = (*spvDescriptorSet0.vp_c0)._m0[100].x;\n    uint chosen =')
        self.assertIn('(*spvDescriptorSet0.vp_c0)._m0[100].x', self.lower(source))

    def test_rewrite_is_idempotent(self):
        once = self.lower(fixture(existing=True))
        self.assertEqual(once, self.lower(once))

    def test_derived_depth_and_feedback_entries_keep_the_builtin(self):
        source = self.lower(fixture(existing=True))
        _, depth = lowering('vs_depth')(source)
        feedback = lowering('vs_tf')(source, [None] * 4)
        for derived in (depth, feedback):
            self.assertNotIn('(*spvDescriptorSet0.vp_c0)._m0[100].y', derived)
            self.assertIn('[[base_instance]]', derived)
            self.assertIn('as_type<float>(gl_BaseInstance)', derived)


if __name__ == '__main__':
    unittest.main()
