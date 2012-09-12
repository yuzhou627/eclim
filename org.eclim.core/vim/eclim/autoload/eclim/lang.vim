" Author:  Eric Van Dewoestine
"
" Description: {{{
"   Common language functionality (validation, completion, etc.) abstracted
"   into re-usable functions.
"
" License:
"
" Copyright (C) 2005 - 2012  Eric Van Dewoestine
"
" This program is free software: you can redistribute it and/or modify
" it under the terms of the GNU General Public License as published by
" the Free Software Foundation, either version 3 of the License, or
" (at your option) any later version.
"
" This program is distributed in the hope that it will be useful,
" but WITHOUT ANY WARRANTY; without even the implied warranty of
" MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
" GNU General Public License for more details.
"
" You should have received a copy of the GNU General Public License
" along with this program.  If not, see <http://www.gnu.org/licenses/>.
"
" }}}

" Global Varables {{{
  if !exists('g:EclimRefactorDiffOrientation')
    let g:EclimRefactorDiffOrientation = 'vertical'
  endif
" }}}

" Script Variables {{{
  let s:update_command = '-command <lang>_src_update -p "<project>" -f "<file>"'
  let s:validate_command = '-command <type>_validate -p "<project>" -f "<file>"'
  let s:undoredo_command = '-command refactor_<operation>'
" }}}

" CodeComplete(command, findstart, base, [options]) {{{
" Handles code completion.
function! eclim#lang#CodeComplete(command, findstart, base, ...)
  if !eclim#project#util#IsCurrentFileInProject(0)
    return a:findstart ? -1 : []
  endif

  let options = a:0 ? a:1 : {}

  if a:findstart
    call eclim#lang#SilentUpdate(get(options, 'temp', 1))

    " locate the start of the word
    let line = getline('.')

    let start = col('.') - 1

    "exceptions that break the rule
    if line[start] =~ '\.'
      let start -= 1
    endif

    while start > 0 && line[start - 1] =~ '\w'
      let start -= 1
    endwhile

    return start
  else
    let offset = eclim#util#GetOffset() + len(a:base)
    let project = eclim#project#util#GetCurrentProjectName()
    let file = eclim#lang#SilentUpdate(get(options, 'temp', 1), 0)
    if file == ''
      return []
    endif

    let command = a:command
    let command = substitute(command, '<project>', project, '')
    let command = substitute(command, '<file>', file, '')
    let command = substitute(command, '<offset>', offset, '')
    let command = substitute(command, '<encoding>', eclim#util#GetEncoding(), '')
    if has_key(options, 'layout')
      let command = substitute(command, '<layout>', options.layout, '')
    endif

    let completions = []
    let results = eclim#ExecuteEclim(command)
    if type(results) != g:LIST_TYPE
      return
    endif

    let open_paren = getline('.') =~ '\%' . col('.') . 'c\s*('
    let close_paren = getline('.') =~ '\%' . col('.') . 'c\s*(\s*)'

    for result in results
      let word = result.completion

      " strip off close paren if necessary.
      if word =~ ')$' && close_paren
        let word = strpart(word, 0, strlen(word) - 1)
      endif

      " strip off open paren if necessary.
      if word =~ '($' && open_paren
        let word = strpart(word, 0, strlen(word) - 1)
      endif

      let menu = eclim#html#util#HtmlToText(result.menu)
      let info = has_key(result, 'info') ?
        \ eclim#html#util#HtmlToText(result.info) : ''

      let dict = {
          \ 'word': word,
          \ 'menu': menu,
          \ 'info': info,
          \ 'dup': 1
        \ }

      call add(completions, dict)
    endfor

    return completions
  endif
endfunction " }}}

" Search(command, singleResultAction, argline) {{{
" Executes a search.
function! eclim#lang#Search(command, singleResultAction, argline)
  let argline = a:argline
  "if argline == ''
  "  call eclim#util#EchoError('You must supply a search pattern.')
  "  return
  "endif

  " check if pattern supplied without -p.
  if argline !~ '^\s*-[a-z]' && argline !~ '^\s*$'
    let argline = '-p ' . argline
  endif

  if !eclim#project#util#IsCurrentFileInProject(0)
    let args = eclim#util#ParseArgs(argline)
    let index = index(args, '-s') + 1
    if index && len(args) > index && args[index] != 'all'
      return
    endif
    let argline .= ' -s all'
  endif

  let search_cmd = a:command
  let project = eclim#project#util#GetCurrentProjectName()
  if project != ''
    let search_cmd .= ' -n "' . project . '"'
  endif

  " no pattern supplied, use element search.
  if argline !~ '-p\>'
    if !eclim#project#util#IsCurrentFileInProject(1)
      return
    endif
    " update the file.
    call eclim#util#ExecWithoutAutocmds('silent update')

    let file = eclim#project#util#GetProjectRelativeFilePath()
    let position = eclim#util#GetCurrentElementPosition()
    let offset = substitute(position, '\(.*\);\(.*\)', '\1', '')
    let length = substitute(position, '\(.*\);\(.*\)', '\2', '')
    let encoding = eclim#util#GetEncoding()
    let search_cmd .= ' -f "' . file . '"' .
      \ ' -o ' . offset . ' -l ' . length . ' -e ' . encoding
  else
    " quote the search pattern
    let search_cmd = substitute(
      \ search_cmd, '\(.*-p\s\+\)\(.\{-}\)\(\s\|$\)\(.*\)', '\1"\2"\3\4', '')
  endif

  let search_cmd .= ' ' . argline

  let workspace = eclim#eclipse#ChooseWorkspace()
  if workspace == '0'
    return ''
  endif

  let port = eclim#client#nailgun#GetNgPort(workspace)
  let results =  eclim#ExecuteEclim(search_cmd, port)
  if type(results) != g:LIST_TYPE
    return
  endif

  if !empty(results)
    call eclim#util#SetLocationList(eclim#util#ParseLocationEntries(results))
    let locs = getloclist(0)
    " if only one result and it's for the current file, just jump to it.
    " note: on windows the expand result must be escaped
    if len(results) == 1 && locs[0].bufnr == bufnr('%')
      if results[0].line != 1 && results[0].column != 1
        lfirst
      endif

    " single result in another file.
    elseif len(results) == 1 && a:singleResultAction != "lopen"
      let entry = getloclist(0)[0]
      call eclim#util#GoToBufferWindowOrOpen
        \ (bufname(entry.bufnr), a:singleResultAction)
      call eclim#util#SetLocationList(eclim#util#ParseLocationEntries(results))
      call eclim#display#signs#Update()

      call cursor(entry.lnum, entry.col)
    else
      exec 'lopen ' . g:EclimLocationListHeight
    endif
    return 1
  else
    if argline !~ '-p\>'
      call eclim#util#EchoInfo("Element not found.")
    else
      let searchedFor = substitute(argline, '.*-p \(.\{-}\)\( .*\|$\)', '\1', '')
      call eclim#util#EchoInfo("Pattern '" . searchedFor . "' not found.")
    endif
  endif

endfunction " }}}

" UpdateSrcFile(validate) {{{
" Updates the src file on the server w/ the changes made to the current file.
function! eclim#lang#UpdateSrcFile(lang, validate)
  let project = eclim#project#util#GetCurrentProjectName()
  if project != ""
    let file = eclim#project#util#GetProjectRelativeFilePath()
    let command = s:update_command
    let command = substitute(command, '<lang>', a:lang, '')
    let command = substitute(command, '<project>', project, '')
    let command = substitute(command, '<file>', file, '')
    if a:validate && !eclim#util#WillWrittenBufferClose()
      let command = command . ' -v'
      if eclim#project#problems#IsProblemsList() &&
       \ g:EclimProjectProblemsUpdateOnSave
        let command = command . ' -b'
      endif
    endif

    let result = eclim#ExecuteEclim(command)
    if type(result) == g:LIST_TYPE && len(result) > 0
      let errors = eclim#util#ParseLocationEntries(
        \ result, g:EclimValidateSortResults)
      call eclim#util#SetLocationList(errors)
    else
      call eclim#util#ClearLocationList('global')
    endif

    call eclim#project#problems#ProblemsUpdate('save')
  elseif a:validate && expand('<amatch>') == ''
    call eclim#project#util#IsCurrentFileInProject()
  endif
endfunction " }}}

" Validate(type, on_save, [filter]) {{{
" Validates the current file. Used by languages which are not validated via
" UpdateSrcFile (pretty much all the xml dialects and wst langs).
function! eclim#lang#Validate(type, on_save, ...)
  if eclim#util#WillWrittenBufferClose()
    return
  endif

  if !eclim#project#util#IsCurrentFileInProject(!a:on_save)
    return
  endif

  let project = eclim#project#util#GetCurrentProjectName()
  let file = eclim#project#util#GetProjectRelativeFilePath()
  let command = s:validate_command
  let command = substitute(command, '<type>', a:type, '')
  let command = substitute(command, '<project>', project, '')
  let command = substitute(command, '<file>', file, '')

  let result = eclim#ExecuteEclim(command)
  if type(result) == g:LIST_TYPE && len(result) > 0
    let errors = eclim#util#ParseLocationEntries(
      \ result, g:EclimValidateSortResults)
    if a:0
      let errors = function(a:1)(errors)
    endif
    call eclim#util#SetLocationList(errors)
  else
    call eclim#util#ClearLocationList()
  endif
endfunction " }}}

" SilentUpdate([temp], [temp_write]) {{{
" Silently updates the current source file w/out validation.
function! eclim#lang#SilentUpdate(...)
  " i couldn't reproduce the issue, but at least one person experienced the
  " cursor moving on update and breaking code completion:
  " http://sourceforge.net/tracker/index.php?func=detail&aid=1995319&group_id=145869&atid=763323
  let pos = getpos('.')
  let file = eclim#project#util#GetProjectRelativeFilePath()
  if file != ''
    try
      if a:0 && a:1
        " don't create temp files if no server is available to clean them up.
        let project = eclim#project#util#GetCurrentProjectName()
        let workspace = eclim#project#util#GetProjectWorkspace(project)
        if workspace != '' && eclim#PingEclim(0, workspace)
          let prefix = '__eclim_temp_'
          let file = fnamemodify(file, ':h') . '/' . prefix . fnamemodify(file, ':t')
          let tempfile = expand('%:p:h') . '/' . prefix . expand('%:t')
          if a:0 < 2 || a:2
            let savepatchmode = &patchmode
            set patchmode=
            exec 'silent noautocmd write! ' . escape(tempfile, ' ')
            let &patchmode = savepatchmode
          endif
        endif
      else
        if a:0 < 2 || a:2
          silent noautocmd update
        endif
      endif
    finally
      call setpos('.', pos)
    endtry
  endif
  return file
endfunction " }}}

" Refactor(command) {{{
" Executes the supplied refactoring command handle error response and
" reloading files that have changed.
function! eclim#lang#Refactor(command)
  let cwd = substitute(getcwd(), '\', '/', 'g')
  let cwd_return = 1

  try
    " turn off swap files temporarily to avoid issues with folder/file
    " renaming.
    let bufend = bufnr('$')
    let bufnum = 1
    while bufnum <= bufend
      if bufexists(bufnum)
        call setbufvar(bufnum, 'save_swapfile', getbufvar(bufnum, '&swapfile'))
        call setbufvar(bufnum, '&swapfile', 0)
      endif
      let bufnum = bufnum + 1
    endwhile

    " cd to the project root to avoid folder renaming issues on windows.
    exec 'cd ' . escape(eclim#project#util#GetCurrentProjectRoot(), ' ')

    let result = eclim#ExecuteEclim(a:command)
    if type(result) != g:LIST_TYPE && type(result) != g:DICT_TYPE
      return
    endif

    " error occurred
    if type(result) == g:DICT_TYPE && has_key(result, 'errors')
      call eclim#util#EchoError(result.errors)
      return
    endif

    " reload affected files.
    let curwin = winnr()
    try
      for info in result
        let newfile = ''
        " handle file renames
        if has_key(info, 'to')
          let file = info.from
          let newfile = info.to
          if has('win32unix')
            let newfile = eclim#cygwin#CygwinPath(newfile)
          endif
        else
          let file = info.file
        endif

        if has('win32unix')
          let file = eclim#cygwin#CygwinPath(file)
        endif

        " ignore unchanged directories
        if isdirectory(file)
          continue
        endif

        " handle current working directory moved.
        if newfile != '' && isdirectory(newfile)
          if file =~ '^' . cwd . '\(/\|$\)'
            while cwd !~ '^' . file . '\(/\|$\)'
              let file = fnamemodify(file, ':h')
              let newfile = fnamemodify(newfile, ':h')
            endwhile
          endif

          if cwd =~ '^' . file . '\(/\|$\)'
            let dir = substitute(cwd, file, newfile, '')
            exec 'cd ' . escape(dir, ' ')
            let cwd_return = 0
          endif
          continue
        endif

        let winnr = bufwinnr(file)
        if winnr > -1
          exec winnr . 'winc w'
          if newfile != ''
            let bufnr = bufnr('%')
            enew
            exec 'bdelete ' . bufnr
            exec 'edit ' . escape(eclim#util#Simplify(newfile), ' ')
          else
            call eclim#util#ReloadRetab()
          endif
        endif
      endfor
    finally
      exec curwin . 'winc w'
      if cwd_return
        exec 'cd ' . escape(cwd, ' ')
      endif
    endtry
  finally
    " re-enable swap files
    let bufnum = 1
    while bufnum <= bufend
      if bufexists(bufnum)
        let save_swapfile = getbufvar(bufnum, 'save_swapfile')
        if save_swapfile != ''
          call setbufvar(bufnum, '&swapfile', save_swapfile)
        endif
      endif
      let bufnum = bufnum + 1
    endwhile
  endtry
endfunction " }}}

" RefactorPreview(command) {{{
" Executes the supplied refactor preview command and opens a corresponding
" window to view that preview.
function! eclim#lang#RefactorPreview(command)
  let result = eclim#ExecuteEclim(a:command)
  if type(result) != g:DICT_TYPE
    return
  endif

  " error occurred
  if has_key(result, 'errors')
    call eclim#util#EchoError(result.errors)
    return
  endif

  let lines = []
  for change in result.changes
    if change.type == 'diff'
      call add(lines, '|diff|: ' . change.file)
    else
      call add(lines, change.type . ': ' . change.message)
    endif
  endfor

  call add(lines, '')
  call add(lines, '|Execute Refactoring|')
  call eclim#util#TempWindow('[Refactor Preview]', lines)
  let b:refactor_command = result.apply

  set ft=refactor_preview
  hi link RefactorLabel Identifier
  hi link RefactorLink Label
  syntax match RefactorLabel /^\s*\w\+:/
  syntax match RefactorLink /|\S.\{-}\S|/

  nnoremap <silent> <buffer> <cr> :call eclim#lang#RefactorPreviewLink()<cr>
endfunction " }}}

" RefactorPreviewLink() {{{
" Called when a user hits <cr> on a link in the refactor preview window,
" issuing a diff for that file.
function! eclim#lang#RefactorPreviewLink()
  let line = getline('.')
  if line =~ '^|'
    let command = b:refactor_command

    let winend = winnr('$')
    let winnum = 1
    while winnum <= winend
      let bufnr = winbufnr(winnum)
      if getbufvar(bufnr, 'refactor_preview_diff') != ''
        exec bufnr . 'bd'
        continue
      endif
      let winnum += 1
    endwhile

    if line == '|Execute Refactoring|'
      call eclim#lang#Refactor(command)
      let winnr = b:winnr
      close
      " the filename might change, so we have to use the winnr to get back to
      " where we were.
      exec winnr . 'winc w'

    elseif line =~ '^|diff|'
      let file = substitute(line, '^|diff|:\s*', '', '')
      let command .= ' -v -d "' . file . '"'

      let diff = eclim#ExecuteEclim(command)
      if type(diff) != g:STRING_TYPE
        return
      endif

      " split relative to the original window
      exec b:winnr . 'winc w'

      if has('win32unix')
        let file = eclim#cygwin#CygwinPath(file)
      endif
      let name = fnamemodify(file, ':t:r')
      let ext = fnamemodify(file, ':e')
      exec printf('silent below new %s.current.%s', name, ext)
      silent 1,$delete _ " counter-act any templating plugin
      exec 'read ' . escape(file, ' ')
      silent 1,1delete _
      let winnr = winnr()
      let b:refactor_preview_diff = 1
      setlocal readonly nomodifiable
      setlocal noswapfile nobuflisted
      setlocal buftype=nofile bufhidden=delete
      diffthis

      let orien = g:EclimRefactorDiffOrientation == 'horizontal' ? '' : 'vertical'
      exec printf('silent below %s split %s.new.%s', orien, name, ext)
      silent 1,$delete _ " counter-act any templating plugin
      call append(1, split(diff, "\n"))
      let b:refactor_preview_diff = 1
      silent 1,1delete _
      setlocal readonly nomodifiable
      setlocal noswapfile nobuflisted
      setlocal buftype=nofile bufhidden=delete
      diffthis
      exec winnr . 'winc w'
    endif
  endif
endfunction " }}}

" RefactorPrompt(prompt) {{{
" Issues the standard prompt for language refactorings.
function! eclim#lang#RefactorPrompt(prompt)
  exec "echohl " . g:EclimInfoHighlight
  try
    " clear any previous messages
    redraw
    echo a:prompt . "\n"
    let response = input("([e]xecute / [p]review / [c]ancel): ")
    while response != '' &&
        \ response !~ '^\c\s*\(e\(xecute\)\?\|p\(review\)\?\|c\(ancel\)\?\)\s*$'
      let response = input("You must choose either e, p, or c. (Ctrl-C to cancel): ")
    endwhile
  finally
    echohl None
  endtry

  if response == ''
    return -1
  endif

  if response =~ '\c\s*\(c\(ancel\)\?\)\s*'
    return 0
  endif

  return response =~ '\c\s*\(e\(execute\)\?\)\s*' ? 1 : 2 " preview
endfunction " }}}

" UndoRedo(operation, peek) {{{
" Performs an undo or redo (operation  = 'undo' or 'redo') for the last
" executed refactoring.
function! eclim#lang#UndoRedo(operation, peek)
  if !eclim#project#util#IsCurrentFileInProject()
    return
  endif

  " update the file before vim makes any changes.
  call eclim#lang#SilentUpdate()
  wall

  let command = s:undoredo_command
  let command = substitute(command, '<operation>', a:operation, '')
  if a:peek
    let command .= ' -p'
    let result = eclim#ExecuteEclim(command)
    if type(result) == g:STRING_TYPE
      call eclim#util#Echo(result)
    endif
    return
  endif

  call eclim#lang#Refactor(command)
endfunction " }}}

" vim:ft=vim:fdm=marker
