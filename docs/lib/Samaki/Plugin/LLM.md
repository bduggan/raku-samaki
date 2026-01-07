NAME
====

Samaki::Plugin::LLM -- Send prompts to an LLM

DESCRIPTION
===========

Send cell content to a Large Language Model using [LLM::DWIM](LLM::DWIM). The LLM provider and model are configured via environment variables (see LLM::DWIM documentation).

OPTIONS
=======

No specific options.

EXAMPLE
=======

    -- llm
    How many roads must a man walk down, before you call him a man?

Output:

    The answer, my friend, is blowin' in the wind.

Example with interpolation:

    -- duck
    select 'earth' as planet;

    -- llm
    Which planet from the sun is 〈 cells(0).rows[0]<planet> 〉?

Output:

    Earth is the third planet from the sun.

