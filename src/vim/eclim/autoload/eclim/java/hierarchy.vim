" Author:  Eric Van Dewoestine
"
" Description: {{{
"   see http://eclim.org/vim/java/hierarchy.html
"
" License:
"
" Copyright (C) 2005 - 2009  Eric Van Dewoestine
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

" Global Variables {{{
if !exists('g:EclimJavaHierarchyDefaultAction')
  let g:EclimJavaHierarchyDefaultAction = 'split'
endif
" }}}

" Script Variables {{{
let s:command_hierarchy =
  \ '-command java_hierarchy -p "<project>" -f "<file>" -o <offset> -e <encoding>'

" }}}

" Hierarchy() {{{
function! eclim#java#hierarchy#Hierarchy()
  if !eclim#project#util#IsCurrentFileInProject()
    return
  endif

  let project = eclim#project#util#GetCurrentProjectName()
  let command = s:command_hierarchy
  let command = substitute(command, '<project>', project, '')
  let command = substitute(command, '<file>', eclim#java#util#GetFilename(), '')
  let command = substitute(command, '<offset>', eclim#util#GetOffset(), '')
  let command = substitute(command, '<encoding>', eclim#util#GetEncoding(), '')
  let result = eclim#ExecuteEclim(command)
  if result == "0"
    return
  endif

  let hierarchy = eval(result)
  let lines = []
  let info = []
  call s:FormatHierarchy(hierarchy, lines, info, '')
  call eclim#util#TempWindow('[Hierarchy]', lines)

  set ft=java
  let b:hierarchy_info = info
  call eclim#util#Echo(b:hierarchy_info[line('.') - 1])

  augroup eclim_java_hierarchy
    autocmd!
    autocmd CursorMoved <buffer>
      \ call eclim#util#Echo(b:hierarchy_info[line('.') - 1])
  augroup END

  noremap <buffer> <silent> <cr>
    \ :call <SID>Open(g:EclimJavaHierarchyDefaultAction)<cr>
  noremap <buffer> <silent> <c-e> :call <SID>Open('edit')<cr>
  noremap <buffer> <silent> <c-s> :call <SID>Open('split')<cr>
  noremap <buffer> <silent> <c-t> :call <SID>Open("tablast \| tabnew")<cr>
endfunction " }}}

" s:FormatHierarchy(hierarchy, lines, indent) {{{
function! s:FormatHierarchy(hierarchy, lines, info, indent)
  call add(a:lines, a:indent . a:hierarchy.name)
  call add(a:info, a:hierarchy.qualified)
  for child in a:hierarchy.children
    call s:FormatHierarchy(child, a:lines, a:info, a:indent . g:EclimIndent)
  endfor
endfunction " }}}

" s:Open(action) {{{
function! s:Open(action)
  let line = line('.')
  let type = b:hierarchy_info[line - 1]
  " go to the buffer that initiated the hierarchy
  exec b:winnr . 'winc w'

  " source the search plugin if necessary
  if !exists("g:EclimJavaSearchSingleResult")
    runtime autoload/eclim/java/search.vim
  endif

  let action = a:action
  let filename = expand('%:p')
  if exists('b:filename')
    let filename = b:filename
    if !eclim#util#GoToBufferWindow(b:filename)
      " if the file is no longer open, open it
      silent! exec action . ' ' . b:filename
      let action = 'edit'
    endif
  endif

  if line != 1
    let saved = g:EclimJavaSearchSingleResult
    try
      let g:EclimJavaSearchSingleResult = action
      if eclim#java#search#SearchAndDisplay('java_search', '-x declarations -p ' . type)
        let b:filename = filename
      endif
    finally
      let g:EclimJavaSearchSingleResult = saved
    endtry
  endif
endfunction " }}}

" vim:ft=vim:fdm=marker
