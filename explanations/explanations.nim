## This module is intended as a way to document return values, error messages,
## or other outcomes of calling a procedure, function, or macro in an in-line
## fashion. When writing good software it's crucial to properly document how it
## works, but how we do it is often error prone and can cause more harm than
## good. This module tries to fix one of the issues with providing good
## documentation. Namely the disassociation with return values and error
## messages from the documentation of them. Say you've created a nice little
## function that can return three different return values. To document this
## you've got a nice table in your documentation, a little something like this:
##
## .. code-block:: nim
##    func ourSuperFunc(value: int): int =
##      ## This procedure can return the following:
##      ## ===  ===============================================
##      ## 0    The value passed in was low (<100)
##      ## 1    The value passed in was medium (>100, < 10_000)
##      ## 2    The value passed in was high (>10_000)
##      ## ===  ===============================================
##      case value:
##      of low(int)..100:
##        return 0
##      of 101..10_000:
##        return 1
##      else:
##        return 2
##
## This looks good, but there is a problem. What happens if we change one of
## the ranges, but forget to update the documentation? Now the documentation is
## lying to us about what the function does which is not good. This can happen
## a lot, especially when multiple people are editing the same code, and
## someone who wasn't aware of the table made a change. To alleviate this issue
## this module implements an ``explained`` pragma, and an ``expl``
## semi-template.
import macros, strutils, sequtils, tables

const exportExplanations {.strdefine.} = ""
var allExplanations {.compileTime.} = initTable[string, tuple[message: string, table: seq[tuple[value, explanation: string]]]]()

proc buildTable(table: seq[tuple[value, explanation: string]]): string {.compileTime.} =
  var
    longestValue = 0
    longestExplanation = 0

  for entry in table:
    longestValue = max(longestValue, entry.value.len)
    longestExplanation = max(longestExplanation, entry.explanation.len)

  longestValue += 2
  longestExplanation += 2

  result = '='.repeat(longestValue-2) & "  " & '='.repeat(longestExplanation-2) & "\n"
  for explanation in table:
    result &= explanation.value &
      ' '.repeat(longestValue - explanation.value.len) &
      explanation.explanation &
      ' '.repeat(longestExplanation - explanation.explanation.len) & "\n"
  result &= '='.repeat(longestValue-2) & "  " & '='.repeat(longestExplanation-2) & "\n"

macro explained*(message: string, procDef: untyped): untyped =
  ## The ``explained`` pragma can be attached to a procedure, a function, or a
  ## macro. It will look through the body of what it's attached to and replace
  ## any ``expl`` instances with the first argument while creating a table of
  ## the value ``repr``'ed and the explanation given. This means that we can
  ## rewrite the example above with:
  ##
  ## .. code-block::
  ##    func ourSuperFunc(value: int): int
  ##      {.explained: "This procedure can return the following:".} =
  ##      case value:
  ##      of low(int)..100:
  ##        return expl(0, "The value passed in was low (<100)")
  ##      of 101..10_000:
  ##        return expl(1, "The value passed in was medium (>100, < 10_000)")
  ##      else:
  ##        return expl(2, "The value passed in was high (>10_000)")
  ## While this doesn't completely remove the possibility of erroneous
  ## documentation, it at least brings the explanation closer to the actual
  ## value. Making it easier to spot and to change when the code is changed.
  ## You can also export the table to a file by passing
  ## ``-d:exportExplanations=<filename.rst>``, which is useful if you are
  ## documenting return codes of a terminal application, or strings echoed
  ## during execution. If you only want this output you must also pass
  ## ``-d:noDocExplanations`` which will remove the explanations table from the
  ## docstring.
  assert(procDef.kind in {nnkProcDef, nnkFuncDef, nnkMacroDef},
    "This pragma can only be applied to a procedure, function, or macro")
  var explanations: seq[tuple[value, explanation: string]]
  proc traverse(node: NimNode): NimNode =
    if node.kind == nnkCall and node[0] == ident "expl":
      explanations.add (node[1].repr, node[2].strVal)
      result = node[1]
    else:
      result = copyNimNode(node)
      for child in node:
        result.add traverse(child)
  result = copyNimTree(procDef)
  result[6] = traverse procDef[6]
  let comment = message.strVal & "\n" & buildTable(explanations)
  when not defined(noDocExplanations):
    if result[6][0].kind == nnkCommentStmt:
      result[6][0].strVal = result[6][0].strVal & "\n\n" & comment
    else:
      let body = result[6]
      result[6] = newStmtList()
      result[6].add newCommentStmtNode(comment)
      for child in body:
        result[6].add child
  if exportExplanations.len > 0:
    writeFile(exportExplanations, comment)
  allExplanations[$procdef[0]] = (message.strVal, explanations)

proc addExplanationImpl(explained: tuple[message, explained: string], procDef: NimNode): NimNode {.compileTime.} =
  assert(procDef.kind in {nnkProcDef, nnkFuncDef, nnkMacroDef},
    "This pragma can only be applied to a procedure, function, or macro")
  assert(allExplanations.hasKey(explained.explained),
    "Explanation for '" & explained.explained & "' not found")
  result = copyNimTree(procDef)
  let message =
    if explained.message.len != 0:
      explained.message & "\n\n" & allExplanations[explained.explained].table.buildTable
    else:
      allExplanations[explained.explained].message & "\n\n" & allExplanations[explained.explained].table.buildTable
  if result[6][0].kind == nnkCommentStmt:
    result[6][0].strVal = result[6][0].strVal & "\n\n" & message
  else:
    let body = result[6]
    result[6] = newStmtList()
    result[6].add newCommentStmtNode(message)
    for child in body:
      result[6].add child

macro addExplanation*(explained: static[tuple[message, explained: string]], procDef: untyped): untyped =
  ## Adds an explanation table and message from another procedure, the first
  ## element in the explained tuple can be set to an extra message to put
  ## before the added table and message.
  addExplanationImpl(explained, procDef)

macro addExplanations*(explained: static[seq[tuple[message, explained: string]]], procDef: untyped): untyped =
  ## Same as ``addExplanation`` but accepts a sequence of tables to add
  assert(procDef.kind in {nnkProcDef, nnkFuncDef, nnkMacroDef},
    "This pragma can only be applied to a procedure, function, or macro")
  for toexplain in explained:
    assert(allExplanations.hasKey(toexplain.explained),
      "Explanation for '" & toexplain.explained & "' not found")
  result = procDef
  for toexplain in explained:
    result = addExplanationImpl(toexplain, result)

macro mergeExplanations*(explained: static[seq[string]], procDef: untyped): untyped =
  ## Takes a list of explained procedures and merges them with this procedures
  ## table, creating one long table with one shared message (the one that was
  ## used for this procedures explanation).
  assert(procDef.kind in {nnkProcDef, nnkFuncDef, nnkMacroDef},
    "This pragma can only be applied to a procedure, function, or macro")
  for tomerge in explained:
    assert(allExplanations.hasKey(tomerge),
      "Explanation for '" & tomerge & "' not found")
  assert(allExplanations.hasKey($procdef[0]),
    "Explanation for '" & $procdef[0] & "' not found")
  result = copyNimTree(procDef)
  var
    comment = result[6][0].strVal
    table = allExplanations[$procdef[0]].table
  comment = comment.splitLines[0..^(4 + table.len)].join("\n")
  for tomerge in explained:
    table = table.concat(allExplanations[tomerge].table)
  comment &= "\n" & buildTable(table)
  result[6][0].strVal = comment


template expl*(value: untyped, explanation: string): untyped {.used.} =
  ## This template only exists to create an error when ``expl`` is used outside
  ## the ``explained`` pragma. See the documentation for ``explained`` to see
  ## how it is meant to be used.
  {.fatal: "expl can't be used outside a valid explained pragma context!".}

when isMainModule and not defined(nimdoc):
  proc hello* {.explained: "This procedure can echo and return the following".} =
    ## This is a test
    echo "Hello world"
    echo expl("This is a test", "When we're testing the explanations module")
    echo "Hello other world"
    quit expl(100, "When normal execution is complete")

  proc world* {.explained: "This can output:", addExplanation: ("", "hello*").} =
    echo expl("This is world", "When we're testing the addExplanation part")

  proc foo* {.explained: "One more test:", addExplanations: @[("test", "hello*"), ("test2", "world*")].} =
    echo expl("This is a test", "With an explanation")

  proc bar* {.explained: "One more test:", mergeExplanations: @["hello*", "world*"].} =
    echo expl("This is a test", "With an explanation")

  hello()
  world()

