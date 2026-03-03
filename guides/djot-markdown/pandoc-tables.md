### Simple tables {-}

A basic simple table...

  Right     Left     Center     Default
-------     ------ ----------   -------
     12     12        12            12
    123     123       123          123

Table:  Demonstration of a simple table.

A simple headerless table without caption:

-------     ------ ----------   -------
     12     12        12             12
    123     123       123           123
-------     ------ ----------   -------

### Multiline tables {-}

The "multiline tables" are interesting when one needs rows
that span multiple lines (in the input text source).

-------------------------------------------------------------
 Centered   Default           Right Left
  Header                    Aligned Aligned
----------- ------- --------------- -------------------------
   First    row                12.0 Example of a row that
                                    spans multiple lines.

  Second    row                 5.0 This row also spans
                                    multiple lines.
-------------------------------------------------------------

Table: Demonstration of a multiline table.

Multiline headerless table:

----------- ------- --------------- -------------------------
   First    row                12.0 Example of a row that
                                    spans multiple lines.

  Second    row                 5.0 Here's another one.
----------- ------- --------------- -------------------------

: Here's a multiline table without a header.

### Grid tables {-}

"Grid tables" can contain interesting things, such as lists...

: Sample grid table.

+---------------+---------------+--------------------+
| Fruit         | Price         | Advantages         |
+===============+===============+====================+
| Bananas       | $1.34         | - built-in wrapper |
|               |               | - bright color     |
+---------------+---------------+--------------------+
| Oranges       | $2.10         | - cures scurvy     |
|               |               | - tasty            |
+---------------+---------------+--------------------+

Grid table with alignments:

+---------------+---------------+--------------------+
| Right         | Left          | Centered           |
+==============:+:==============+:==================:+
| Bananas       | $1.34         | built-in wrapper   |
+---------------+---------------+--------------------+

Headerless grid table with alignments.

+--------------:+:--------------+:------------------:+
| Right         | Left          | Centered           |
+--------------:+:--------------+:------------------:+

### Pipe tables {-}

And "pipe tables" should of course still work...

| Right | Left | Default | Center |
|------:|:-----|---------|:------:|
|   12  |  12  |    12   |    12  |
|  123  |  123 |   123   |   123  |

  : Demonstration of a pipe table.

