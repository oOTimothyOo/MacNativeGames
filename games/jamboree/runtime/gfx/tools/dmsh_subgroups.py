"""Preserve real vertex subgroups when Metal cannot expose the lane-ID attribute.

SPIRV-Cross accepts vertex ballots, votes and shuffles, but rejects the subgroup
lane-ID input. For vertex programs without user attributes, temporarily expose
lane ID / LtMask as named inputs, then replace those inputs with local values.
No subgroup instruction or atomic operation is scalarized. Other input forms
retain the existing translation path.
"""
import re
import struct
from pathlib import Path

NAMES = {41: 'dm_native_sg_lane', 4420: 'dm_native_sg_lt'}
HELPERS = '''
// Prefix rank counts active lanes below this one. Select that rank's bit in the
// active mask to recover the physical lane, including divergent masks with holes.
inline uint dm_native_lane_id() {
    ulong mask = (simd_vote::vote_t)simd_ballot(true);
    uint rank = simd_prefix_exclusive_sum(1u);
    for (uint k = 0; k < rank; k++) mask &= mask - 1;
    return uint(ctz(mask));
}
inline uint4 dm_native_lt_mask() {
    ulong mask = (1ul << dm_native_lane_id()) - 1ul;
    return uint4(uint(mask), uint(mask >> 32), 0u, 0u);
}
'''


def instruction(op, *args):
    return [(len(args) + 1) << 16 | op, *args]


def words_string(value):
    data = value.encode() + b'\0'
    data += b'\0' * (-len(data) % 4)
    return list(struct.unpack('<%dI' % (len(data) // 4), data))


def rewrite(path):
    """Rewrite only a recognized input interface; return False without writing otherwise."""
    path = Path(path)
    data = path.read_bytes()
    if len(data) < 20 or len(data) % 4:
        return False
    words = list(struct.unpack('<%dI' % (len(data) // 4), data))
    if words[0] != 0x07230203:
        return False
    code, at = [], 5
    while at < len(words):
        n = words[at] >> 16
        if not n or at + n > len(words):
            return False
        code.append(words[at:at + n]); at += n
    op = lambda x: x[0] & 65535
    entries = [x for x in code if op(x) == 15]
    if len(entries) != 1 or entries[0][1] != 0:
        return False
    if any(op(x) == 71 and x[2] == 30 for x in code):
        return False  # user attributes require a separate interface allocation
    ids = {x[1]: x[3] for x in code if op(x) == 71 and x[2] == 11 and x[3] in NAMES}
    if not ids:
        return False
    if any(op(x) == 71 and x[2] == 11 and x[3] in {36, 4416, 4417, 4418, 4419} for x in code):
        return False
    variables = {x[2]: x for x in code if op(x) == 59}
    if any(i not in variables or variables[i][3] != 1 for i in ids):
        return False
    if any(op(x) in (5, 6) and b'dm_native_' in struct.pack('<%dI' % (len(x) - 2), *x[2:]) for x in code):
        return False
    out, named = [], False
    for x in code:
        o = op(x)
        if o == 5 and x[1] in ids:
            continue
        if o in (71, 72) and not named:
            out.extend(instruction(5, i, *words_string(NAMES[k])) for i, k in ids.items())
            named = True
        if o == 71 and x[1] in ids and x[2] == 11:
            x = instruction(71, x[1], 30, 31 if ids[x[1]] == 41 else 30)
        out.append(x)
    flat = words[:5] + [n for x in out for n in x]
    path.write_bytes(struct.pack('<%dI' % len(flat), *flat))
    return True


def metal(source):
    """Replace the temporary attributes with entry-local, real-subgroup values."""
    present = []
    for name, fn in (('dm_native_sg_lane', 'dm_native_lane_id()'), ('dm_native_sg_lt', 'dm_native_lt_mask()')):
        source, count = re.subn(r'^\s*(?:uint|uint4)\s+' + name + r'\s*\[\[attribute\(\d+\)\]\];\s*$', '', source, flags=re.M)
        if count:
            if count != 1:
                raise ValueError('duplicate subgroup input')
            present.append((name, fn))
            source = re.sub(r'\b\w+\.' + name + r'\b', name, source)
    if not present or re.search(r'\[\[attribute\((?:30|31)\)\]\]', source):
        raise ValueError('unrecognized subgroup input layout')
    for name in re.findall(r'struct (\w+)\s*\{\s*\};', source):
        source = re.sub(r'struct ' + name + r'\s*\{\s*\};', '', source)
        source = re.sub(r'\b' + name + r'\s+\w+\s*\[\[stage_in\]\]\s*,?\s*', '', source)
    entry = re.search(r'\bvertex\s+\w+\s+main0\s*\(.*?\)\s*\{', source, re.S)
    if not entry:
        raise ValueError('vertex entry missing')
    locals_ = '\n' + ''.join('    ' + ('uint4' if name.endswith('_lt') else 'uint') + ' ' + name + ' = ' + fn + ';\n' for name, fn in present)
    source = source[:entry.end()] + locals_ + source[entry.end():]
    return '#include <metal_stdlib>\nusing namespace metal;\n' + HELPERS + '\n' + source
