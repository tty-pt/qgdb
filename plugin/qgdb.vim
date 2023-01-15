" TODO detect "running" var correctly
" globals and commands {{{

let s:file = ""
let s:args = ""
let s:gdbbuf = 0
let s:gdbw = 0
let s:file_missing = 1
let s:stopped = 1
let s:running = 0
let g:sourcew = 0
if !exists("g:gdb_sudo")
	let g:gdb_sudo = 0
endif
let s:dirname = ""
let s:bplocs = {}
let s:bpnums = {}
let g:gdb_prog = "egdb"
let g:sudo_prog = "sudo"

command! -nargs=1 Args let s:args = <q-args>
command! -nargs=1 File let s:file = <q-args>
command! DebugFocus call win_gotoid(s:gdbw)
command! Stop call term_sendkeys(s:gdbbuf, '')

command! -nargs=1 Gdb call s:GdbCmd(<q-args>)
command! StartRun call s:StartRun()
command! GdbStart call s:GdbStart()
command! Run call s:Run()
command! Break call s:Break()
command! Clear call s:Clear()
command! Continue call s:Continue()
command! GdbQuit call s:GdbCmd("quit")

" }}}

func! s:GdbCmd(cmd)
	call term_sendkeys(s:gdbbuf, '' . a:cmd . '')
endfunc

" start & run {{{

func! s:StartRun()
	if s:GdbStart()
		call s:Run()
	endif
endfunc

func! s:GdbStart()
	if s:gdbw != 0
		echom "Gdb already started"
		return 0
	endif
	let g:sourcew = win_getid()
	if g:gdb_sudo != 0
		let s:gdb_command = G:sudo_prog . ' ' . g:gdb_prog . ' -quiet -f'
	else
		let s:gdb_command = g:gdb_prog . ' -quiet -f'
	endif
	let s:dirname = fnamemodify(expand(s:file), ":h") . '/'
	if filereadable(s:file)
		let s:gdb_command = s:gdb_command . ' ' . s:file
		let s:file_missing = 0
		let s:stopped = 1
	endif

	vert let s:gdbbuf = term_start(s:gdb_command, {
			\ 'exit_cb': function('s:GdbQuit'),
			\ 'out_cb': function('s:GdbOut'),
			\ })

	let s:gdbw = win_getid()
	call win_gotoid(g:sourcew)
	call s:GdbCmd('set args ' . s:args)
	return 1
endfunc

func! s:Run()
	if !filereadable(s:file)
		" let s:file_missing = 1
		echom 'Debug File not readable. Make?'
		return
	endif
	if s:file_missing == 1
		call s:GdbCmd('file ' . s:file)
		let s:file_missing = 0
	endif

	call s:GdbCmd('run')
	let s:stopped = 0
	let s:running = 1
endfunc

" }}}

" Interrupt {{{

func! s:GdbCmdI(cmd)
	let do_cont = 0
	if !s:stopped
		Stop
		let do_cont = 1
	endif

	call s:GdbCmd(a:cmd)

	if do_cont
		call s:Continue()
	endif
endfunc

func! s:B2S(id)
  return 103 + a:id
endfunc

func! s:BKCur()
	let fname = fnameescape(expand('%:t'))
	let linen = line('.')
	return printf("%s:%d", fname, linen)
endfunc

func! s:Break()
	call s:GdbCmdI('break ' . s:BKCur())
endfunc

sign define gdb text=! texthl=Error

func! s:BpCacheDel(bk)
	let bn = s:bplocs[a:bk]
	unlet s:bpnums[bn]
	unlet s:bplocs[a:bk]
	exe 'sign unplace ' . s:B2S(bn)
	return bn
endfunc

func! s:Clear()
	let bn = s:BpCacheDel(s:BKCur())
	call s:GdbCmdI('del ' . bn)
endfunc

func! s:Continue()
	if s:running == 1
		call s:GdbCmd("cont")
	endif
endfunc

" }}}

func! s:GdbQuit(a, b)
	call win_gotoid(s:gdbw)
	let id = win_getid()
	if id == s:gdbw
		quit
	endif
	let s:gdbw = 0
	call g:GdbQuit()
endfunc

" Parse {{{

func! s:BpCacheAdd(bn, fname, linen)
	let bk = a:fname . ':' . a:linen
	let s:bplocs[bk] = a:bn
	let s:bpnums[a:bn] = bk
	let fname = s:dirname . a:fname
	if bufwinnr(fname) <= 0
		exec 'badd ' . fname
	endif
	exe 'sign place ' . s:B2S(a:bn) . ' line=' . a:linen
				\ . ' name=gdb file=' . fname
endfunc

func! s:BpSet(msg)
	let line = a:msg[11:]
	let bn = str2nr(line)
	let linep = split(line, ' ')
	if len(linep) == 7
		let fname = linep[4][:-2]
		let linen = linep[6]
	else
		let fnp = split(linep[3][:-2], ':')
		let fname = fnp[0]
		let linen = fnp[1]
	endif
	let linen = str2nr(linen)
	call s:BpCacheAdd(bn, fname, linen)
endfunc

func! s:GdbParse(msg)
	let msg = a:msg
	if msg =~ '^Starting program.*'
		let s:stopped = 0
		call g:Run()
	elseif msg =~ '^Program received signal.*'
		let s:stopped = 1
		call g:Stop()
	elseif msg =~ '^Continuing\.'
		let s:stopped = 0
		call g:Continue()
	elseif msg =~ '^Breakpoint .* at 0x.*'
		call s:BpSet(msg)
	elseif msg =~ '^Breakpoint .*'
		let bn = matchstr(msg, '\d\+')
		let nbk = matchstr(msg, '\S\+:\d\+$')
		let nbks = split(nbk, ':')
		let fname = nbks[0]
		let linen = str2nr(nbks[1])
		let bk = s:bpnums[bn]
		if bk != nbk
			call s:BpCacheDel(bk)
			call s:BpCacheAdd(bn, fname, linen)
		endif
		let pw = win_getid()
		call win_gotoid(g:sourcew)
		if win_getid() != g:sourcew
			new
			let g:sourcew = win_getid()
		endif
		if pw == s:gdbw
			win_gotoid(s:gdbw)
		endif
		exe 'sign jump ' . s:B2S(s:bplocs[nbk]) . ' file=' . s:dirname . fname
	else
		call g:GdbOut(msg)
	endif
endfunc

func! s:GdbOut(chan, msg)
	let s:lmsg = ""
	let msgs = split(a:msg, "\r")
	for msg in msgs
		if msg[0] == "\n"
			let msg = msg[1:]
		endif
		if msg =~ '^    '
			let s:lmsg = s:lmsg . ' ' . msg[4:]
		else
			call s:GdbParse(s:lmsg)
			let s:lmsg = msg
		endif
	endfor
	call s:GdbParse(s:lmsg)
endfunc

func! g:GdbStopped()
	return s:stopped
endfunc

" }}}
