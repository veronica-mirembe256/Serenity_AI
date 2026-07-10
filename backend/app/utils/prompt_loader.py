"""
app/utils/prompt_loader.py — Jinja2-based prompt template renderer.

All prompts are stored as .j2 files under app/prompts/.
No prompt strings are hardcoded in Python files.
"""

from pathlib import Path
from jinja2 import Environment, FileSystemLoader, StrictUndefined

_PROMPTS_DIR = Path(__file__).parent.parent / "prompts"

_env = Environment(
    loader=FileSystemLoader(str(_PROMPTS_DIR)),
    undefined=StrictUndefined,   # blow up loudly on missing variables
    trim_blocks=True,
    lstrip_blocks=True,
)


def render_prompt(template_name: str, **kwargs: object) -> str:
    """
    Render a Jinja2 prompt template.

    Args:
        template_name:  Filename relative to app/prompts/ (e.g. "reflection.j2").
        **kwargs:       Variables to inject into the template.

    Returns:
        Rendered string ready to send to the LLM.
    """
    template = _env.get_template(template_name)
    return template.render(**kwargs)
