"""Quote inert transport strings with Unicode control escapes accepted by model consumers."""

def quoted_string(value: str) -> str:
    """Use Lean's Unicode escapes for controls; JSON's backspace/formfeed escapes differ."""
    escapes = {ord('"'): '\\"', ord('\\'): '\\\\'}
    escapes.update({number: f"\\u{number:04x}" for number in range(32)})
    return '"' + value.translate(escapes) + '"'

