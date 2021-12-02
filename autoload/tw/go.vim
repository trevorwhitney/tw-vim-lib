" tw#go#testName returns the name of the test function that preceeds the
" cursor. It will combine nested tests with a / to allow you to run the
" closest nested test to the cursor
function tw#go#testName() abort
  " finding the test name relies on the code being correctly formatted
  lua vim.lsp.buf.formatting()

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

  let l:nextInnerTest = tw#go#findNextInnerTest(l:innerTest[0], l:innerTest[1], l:outerTest)
  while l:nextInnerTest[0] != 0 && l:nextInnerTest[0] >= l:outerTest
    let l:testNameChain = tw#go#getInnerTestName(l:nextInnerTest[0]) . '/' . l:testNameChain
    let l:nextInnerTest = tw#go#findNextInnerTest(l:nextInnerTest[0], l:nextInnerTest[1], l:outerTest)
  endwhile

  call setpos('.', l:startingPos)
  return l:parentName . '/' . l:testNameChain
endfunction

function tw#go#getInnerTestName(line) abort
  let l:line = getline(a:line)
  return substitute(split(split(l:line, "\"")[1], "\"")[0], ' ', '_', 'g')
endfunction

function tw#go#findNextInnerTest(line, column, outer) abort
  " return 0 if we've gone past the outer test func
  if a:line <= a:outer
    return 0
  endif

  call cursor(a:line - 1, a:column)
  let l:innerTestPos = searchpos('t.Run("', 'bcnW')

  " findNextInnerTest relies on nested tests being formatted correctly
  " if there was no match found, or that match is at a deeper or equal
  " nesting level (based on column), then it's not a part of the test
  " chain we're looking for
  "
  " no match found
  if l:innerTestPos[0] == 0
    return 0
  endif

  " found a deeper and equally nested test, keep going
  if l:innerTestPos[1] >= a:column
    return tw#go#findNextInnerTest(l:innerTestPos[0] - 1, a:column, a:outer)
  endif

  return l:innerTestPos
endfunction

"TODO: these functions could be smarter and could parse the current file to
"look for relevant build tags at the top of the file
function! tw#go#dlvTestFocused(...)
  let l:buildFlags = (a:0 > 0) ? join(a:000, ',') : ""

  let l:testName = tw#go#testName()
  let l:separator = tw#util#shellCommandSeperator()

  if l:testName !=? ''
    if len(l:buildFlags) > 0
      call delve#dlvTest(expand('%:p:h'), '--build-flags="-tags=' . l:buildFlags . '"', '--', '-test.run', l:testName)
    else
      call delve#dlvTest(expand('%:p:h'), '--', '-test.run', l:testName)
    endif
  else
    echo 'No test found'
  endif
endfunction

function! tw#go#golangTestFocusedWithTags(...)
  let l:buildFlags = (a:0 > 0) ? join(a:000, ',') : ''

  let l:testName = tw#go#testName()
  let l:separator = tw#util#shellCommandSeperator()

  if len(l:testName) > 0
    if len(l:buildFlags) > 0
      call VimuxRunCommand("cd " . GolangCwd() . " " . l:separator . " clear " . l:separator . " go test " . '-tags="' . l:buildFlags . '" ' . GolangFocusedCommand(l:testName) . " -v " . GolangCurrentPackage())
    else
      call VimuxRunCommand("cd " . GolangCwd() . " " . l:separator . " clear " . l:separator . " go test " . GolangFocusedCommand(l:testName) . " -v " . GolangCurrentPackage())
    endif
  else
    echo 'No test found'
  endif
endfunction
