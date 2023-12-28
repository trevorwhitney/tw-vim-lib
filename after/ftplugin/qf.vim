highlight TestOk    ctermbg=green
highlight TestError ctermbg=red

syn match TestOk    "\<Ok:"
syn match TestError "\<Err:"

syn match TestOk    "\<✓"
syn match TestOk    "\<PASS"

syn match TestOk    "\<✓"
syn match TestOk    "|| PASS"
syn match TestOk    "\<|| PASS"
