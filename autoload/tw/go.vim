" tw#go#testName returns the name of the test function that preceeds the
" cursor. It will combine nested tests with a / to allow you to run the
" closest nested test to the cursor
function tw#go#testName() abort
  " search flags legend (used only)
  " 'b' search backward instead of forward
  " 'c' accept a match at the cursor position
  " 'n' do Not move the cursor
  " 'W' don't wrap around the end of the file
  "
  " for the full list
  " :help search
  let l:outerTest = search('func \(Test\|Example\)', "bcnW")
  " Try to find an inner test that is declared before the current cursor
  " position. We use searchpos to get a column as well, which is useful
  " for finding tests at the correct nesting level to determine the correct
  " chain.
  let l:innerTest = searchpos('t.Run("', "bcnW")

  if l:outerTest == 0
    return ''
  endif

  let l:parentLine = getline(l:outerTest)
  let l:parentName = split(split(l:parentLine, ' ')[1], '(')[0]

  " if there is no inner test, or the inner test is above the parent in
  " the file, just return the parent test name
  if l:innerTest[0] == 0 || l:innerTest[0] <= l:outerTest
    return l:parentName
  endif

  " since there was an inner test, we need a place to start building
  " our test name chain
  let l:testNameChain = tw#go#getInnerTestName(l:innerTest[0])

  " findNextInnerTest needs to move the cursor, so stash
  " our current position
  let l:startingPos = getcurpos()

  let l:nextInnerTest = tw#go#findNextInnerTest(l:innerTest[0], l:innerTest[1])
  while l:nextInnerTest[0] != 0 && l:nextInnerTest[0] >= l:outerTest
    let l:testNameChain = tw#go#getInnerTestName(l:nextInnerTest[0]) . '/' . l:testNameChain
    let l:nextInnerTest = tw#go#findNextInnerTest(l:nextInnerTest[0], l:nextInnerTest[1])
  endwhile

  call cursor(l:startingPos[1], l:startingPos[2])
  return l:parentName . '/' . l:testNameChain
endfunction

function tw#go#getInnerTestName(line) abort
  let l:line = getline(a:line)
  return substitute(split(split(l:line, "\"")[1], "\"")[0], ' ', '_', 'g')
endfunction

function tw#go#findNextInnerTest(line, column) abort
  call cursor(a:line - 1, a:column)
  let l:innerTestPos = searchpos('t.Run("', 'bcnW')

  " findNextInnerTest relies on nested tests being formatted correctly
  " if there was no match found, or that match is at a deeper or equal
  " nesting level (based on column), then it's not a part of the test
  " chain we're looking for
  if l:innerTestPos[0] == 0 || l:innerTestPos[1] >= a:column
    return 0
  endif

  return l:innerTestPos
endfunction
