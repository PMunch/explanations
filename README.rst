============
explanations
============

This module is intended as a way to document return values, error messages,
or other outcomes of calling a procedure, function, or macro in an in-line
fashion. When writing good software it's crucial to properly document how it
works, but how we do it is often error prone and can cause more harm than
good. This module tries to fix one of the issues with providing good
documentation. Namely the disassociation with return values and error
messages from the documentation of them. Say you've created a nice little
function that can return three different return values. To document this
you've got a nice table in your documentation, a little something like this:

.. code-block:: nim
   func ourSuperFunc(value: int): int =
     ## This procedure can return the following:
     ## ===  ===============================================
     ## 0    The value passed in was low (<100)
     ## 1    The value passed in was medium (>100, < 10_000)
     ## 2    The value passed in was high (>10_000)
     ## ===  ===============================================
     case value:
     of low(int)..100:
       return 0
     of 101..10_000:
       return 1
     else:
       return 2

This looks good, but there is a problem. What happens if we change one of
the ranges, but forget to update the documentation? Now the documentation is
lying to us about what the function does which is not good. This can happen
a lot, especially when multiple people are editing the same code, and
someone who wasn't aware of the table made a change. To alleviate this issue
this module implements an ``explained`` pragma, and an ``expl``
semi-template.

Macros
======

.. code-block:: nim
  macro explained*(message: string, procDef: untyped): untyped

The ``explained`` pragma can be attached to a procedure, a function, or a
macro. It will look through the body of what it's attached to and replace
any ``expl`` instances with the first argument while creating a table of
the value ``repr``'ed and the explanation given. This means that we can
rewrite the example above with:

.. code-block::
   func ourSuperFunc(value: int): int
     {.explained: "This procedure can return the following:".} =
     case value:
     of low(int)..100:
       return expl(0, "The value passed in was low (<100)")
     of 101..10_000:
       return expl(1, "The value passed in was medium (>100, < 10_000)")
     else:
       return expl(2, "The value passed in was high (>10_000)")
While this doesn't completely remove the possibility of erroneous
documentation, it at least brings the explanation closer to the actual
value. Making it easier to spot and to change when the code is changed.
You can also export the table to a file by passing
``-d:exportExplanations=<filename.rst>``, which is useful if you are
documenting return codes of a terminal application, or strings echoed
during execution. If you only want this output you must also pass
``-d:noDocExplanations`` which will remove the explanations table from the
docstring.

.. code-block:: nim
  macro addExplanation*(explained: static[tuple[message, explained: string]], procDef: untyped): untyped

Adds an explanation table and message from another procedure, the first
element in the explained tuple can be set to an extra message to put
before the added table and message.

.. code-block:: nim
  macro addExplanations*(explained: static[seq[tuple[message, explained: string]]], procDef: untyped): untyped

Same as ``addExplanation`` but accepts a sequence of tables to add

.. code-block:: nim
  macro mergeExplanations*(explained: static[seq[string]], procDef: untyped): untyped

Takes a list of explained procedures and merges them with this procedures
table, creating one long table with one shared message (the one that was
used for this procedures explanation).

Templates
=========

.. code-block:: nim
  template expl*(value: untyped, explanation: string): untyped {.used.}

This template only exists to create an error when ``expl`` is used outside
the ``explained`` pragma. See the documentation for ``explained`` to see
how it is meant to be used.
