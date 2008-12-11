" Author:  Eric Van Dewoestine
" Version: $Revision$
"
" Description: {{{
"   see http://eclim.sourceforge.net/vim/php/search.html
"
" License:
"
" Copyright (C) 2005 - 2008  Eric Van Dewoestine
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

" Command Declarations {{{
if !exists(":PhpFindDefinition")
  command -buffer PhpFindDefinition :call eclim#php#search#FindByContext('declarations')
endif
if !exists(":PhpSearch")
  command -buffer -nargs=*
    \ -complete=customlist,eclim#php#search#CommandCompletePhpSearch
    \ PhpSearch :call eclim#php#search#Search('<args>')
endif
if !exists(":PhpSearchContext")
  command -buffer PhpSearchContext :call eclim#php#search#SearchContext()
endif
" }}}

" vim:ft=vim:fdm=marker
