NAME
====

Samaki::Plugin::Text -- Write text content to a file

DESCRIPTION
===========

Write cell content to a text file. Supports special `[link:pagename]` syntax for creating links to other Samaki pages.

OPTIONS
=======

No specific options.

EXAMPLE
=======

    -- text:notes.txt
    This is some text content.

    You can reference other pages: [link:otherpage]

Output: Creates `notes.txt` with the content. When displayed, `[link:otherpage]` is rendered as a clickable link that loads the "otherpage" notebook.

Example with interpolation:

    -- duck
    select 'Alice' as name, 30 as age;

    -- text:summary.txt
    The user 〈 cells(0).rows[0]<name> 〉 is 〈 cells(0).rows[0]<age> 〉 years old.

Output in `summary.txt`:

    The user Alice is 30 years old.

