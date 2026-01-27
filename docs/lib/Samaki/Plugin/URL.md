NAME
====

Samaki::Plugin::URL -- Fetch a URL using curl

DESCRIPTION
===========

Use curl to fetch a url and write it into the output file.

CONFIGURATION
=============

None.

EXAMPLE
=======

    ```
    -- url:data.json
    https://example.com/data.json
    ```

This will write to data.json. Note that the output file is take from the cell output name + extension.

