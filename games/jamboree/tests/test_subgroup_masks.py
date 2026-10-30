"""Synthetic vertex SPIR-V: component reads of singleton subgroup masks."""
import ast
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1] / 'runtime/gfx/tools'
tree = ast.parse((TOOLS / 'dmsh_build.py').read_text())
names = {'SG_OPS', 'SG_BUILTINS', 'spv_single_lane', '_ep_drop'}
nodes = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in names
         or isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id in names for t in n.targets)]
namespace = {'struct': struct}
exec(compile(ast.Module(body=nodes, type_ignores=[]), str(TOOLS / 'dmsh_build.py'), 'exec'), namespace)

def inst(op, *args):
    return [(len(args) + 1) << 16 | op, *args]

def string_words(text):
    value = text.encode() + b'\0'
    value += b'\0' * (-len(value) % 4)
    return list(struct.unpack('<' + 'I' * (len(value) // 4), value))

def vertex(mask=4420, component=0, dynamic=False, escape=False):
    # Position.x consumes the component, so it cannot disappear as unused input.
    body = []
    for args in ((17, 1), (17, 61), (17, 64), (17, 4423)):
        body += inst(*args)
    body += inst(10, *string_words('SPV_KHR_shader_ballot'))
    body += inst(14, 0, 1)
    body += inst(15, 0, 16, *string_words('main'), 14, 15)
    body += inst(71, 14, 11, mask) + inst(71, 15, 11, 0)
    for args in ((19, 1), (22, 2, 32), (23, 3, 2, 4), (21, 4, 32, 0),
                 (23, 5, 4, 4), (20, 6), (32, 7, 1, 5), (32, 8, 1, 4),
                 (32, 9, 3, 3), (33, 10, 1), (43, 4, 11, component),
                 (43, 2, 12, 0), (43, 2, 13, 0x3f800000),
                 (59, 7, 14, 1), (59, 9, 15, 3), (54, 1, 16, 0, 10), (248, 17)):
        body += inst(*args)
    if dynamic:
        body += inst(128, 4, 22, 11, 11)  # a computed index must not be guessed
    body += inst(65, 8, 18, 14, 22 if dynamic else 11)
    if escape:
        body += inst(83, 8, 22, 18)  # an escaping pointer is deliberately unsupported
    body += inst(61, 4, 19, 18) + inst(112, 2, 20, 19)
    body += inst(80, 3, 21, 20, 12, 12, 13) + inst(62, 15, 21) + inst(253) + inst(56)
    words = [0x07230203, 0x00010300, 0, 23, 0] + body
    return struct.pack('<' + 'I' * len(words), *words)

def instructions(data):
    w = struct.unpack('<' + 'I' * (len(data) // 4), data)
    i = 5
    while i < len(w):
        count = w[i] >> 16
        yield w[i:i + count]
        i += count

class SubgroupMaskTests(unittest.TestCase):
    def test_all_mask_components(self):
        for mask in (4416, 4417, 4418, 4419, 4420):
            for component in range(4):
                with self.subTest(mask=mask, component=component), tempfile.TemporaryDirectory() as work:
                    path = Path(work) / 'vertex.spv'
                    path.write_bytes(vertex(mask, component))
                    self.assertTrue(namespace['spv_single_lane'](path))
                    ops = list(instructions(path.read_bytes()))
                    constants = {x[2]: x[3] for x in ops if x[0] & 65535 == 43 and x[1] == 4}
                    load = next(x for x in ops if x[0] & 65535 == 83 and x[2] == 19)
                    self.assertEqual(constants[load[3]], int(component == 0 and mask in (4416, 4417, 4419)))
                    self.assertFalse(any(x[0] & 65535 == 65 for x in ops))

    def test_unknown_component_leaves_input_unchanged(self):
        with tempfile.TemporaryDirectory() as work:
            path = Path(work) / 'vertex.spv'
            original = vertex(dynamic=True)
            path.write_bytes(original)
            self.assertFalse(namespace['spv_single_lane'](path))
            self.assertEqual(path.read_bytes(), original)

    def test_pointer_escape_leaves_input_unchanged(self):
        with tempfile.TemporaryDirectory() as work:
            path = Path(work) / 'vertex.spv'
            original = vertex(escape=True)
            path.write_bytes(original)
            self.assertFalse(namespace['spv_single_lane'](path))
            self.assertEqual(path.read_bytes(), original)

    @unittest.skipUnless(shutil.which('spirv-cross'), 'SPIRV-Cross is not installed')
    def test_spirv_cross_accepts_rewritten_vertex(self):
        with tempfile.TemporaryDirectory() as work:
            path = Path(work) / 'vertex.spv'
            path.write_bytes(vertex())
            self.assertTrue(namespace['spv_single_lane'](path))
            result = subprocess.run(['spirv-cross', str(path), '--msl', '--msl-version', '31000'], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('vertex', result.stdout)

if __name__ == '__main__':
    unittest.main()
