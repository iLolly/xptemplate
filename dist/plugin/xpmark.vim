if exists("g:__XPMARK_VIM__")
    finish
endif
let g:__XPMARK_VIM__ = 1
com! XPMgetSID let s:sid =  matchstr("<SID>", '\zs\d\+_\ze')
XPMgetSID
delc XPMgetSID
runtime plugin/debug.vim
let g:xpm_mark = 'p'
let g:xpm_mark_nextline = 'l'
let g:xpm_changenr_level = 1000
let s:insertPattern = '[i]'
let g:XPM_RET = {
            \   'likely_matched' : {},
            \   'no_updated_made' : {},
            \   'undo_redo' : {},
            \   'updated' : {},
            \}
let s:log = CreateLogger( 'warn' )
let s:log = CreateLogger( 'debug' )
let g:XPMpreferLeft = 'l'
let g:XPMpreferRight = 'r'
fun! XPMadd( name, pos, prefer ) 
    if &l:statusline !~ 'XPMautoUpdate'
        let &l:statusline  .= '%{XPMautoUpdate("statusline")}'
    endif
    let d = s:bufData()
    let prefer = a:prefer == 'l' ? 0 : 1
    if has_key( d.marks, a:name )
        call d.removeMark( a:name )
    endif
    let d.marks[ a:name ] = a:pos + [ len( getline( a:pos[0] ) ), prefer ]
    call d.addMarkOrder( a:name )
endfunction 
fun! XPMhere( name, prefer ) 
    call XPMadd( a:name, [ line( "." ), col( "." ) ], a:prefer )
endfunction 
fun! XPMremove( name ) 
    let d = s:bufData()
    call d.removeMark( a:name )
endfunction 
fun! XPMremoveMarkStartWith(prefix) 
    let d = s:bufData()
    for key in keys( d.marks )
        if key =~# '^\V' . a:prefix
            call d.removeMark( key )
        endif
    endfor
endfunction 
fun! XPMflush() 
    let d = s:bufData()
    let d.marks = {}
    let d.orderedMarks = []
    let d.markHistory[ changenr() ] = { 'dict' : d.marks, 'list': d.orderedMarks }
    let d.changeLikelyBetween  = { 'start' : '', 'end' : '' }
endfunction 
fun! XPMgoto( name ) 
    let d = s:bufData()
    if has_key( d.marks, a:name )
        let pos = d.marks[ a:name ][ : 1 ]
        call cursor( pos )
    endif
endfunction 
fun! XPMpos( name ) 
    let d = s:bufData()
    if has_key( d.marks, a:name )
        return d.marks[ a:name ][ : 1 ]
    endif
    return [0, 0]
endfunction 
fun! XPMposList( ... )
    let d = s:bufData()
    let list = []
    for name in a:000
        if has_key( d.marks, name )
            call add( list, d.marks[ name ][ : 1 ] )
        else
            call add( list, [0, 0] )
        endif
    endfor
    return list
endfunction
fun! XPMsetLikelyBetween( start, end ) 
    let d = s:bufData()
    Assert has_key( d.marks, a:start )
    Assert has_key( d.marks, a:end )
    let d.changeLikelyBetween = { 'start' : a:start, 'end' : a:end }
endfunction 
fun! XPMsetUpdateStrategy( mode ) 
    let d = s:bufData()
    if a:mode == 'manual'
        let d.updateStrategy = a:mode
    elseif a:mode == 'normalMode'
        let d.updateStrategy = a:mode
    elseif a:mode == 'insertMode'
        let d.updateStrategy = a:mode
    else
        let d.updateStrategy = 'auto'
    endif
endfunction 
fun! XPMupdateSpecificChangedRange(start, end) 
    let d = s:bufData()
    let nr = changenr()
    if nr != d.lastChangenr
        call d.snapshot()
    endif
    call d.initCurrentStat()
    let rc = d.updateWithNewChangeRange( a:start, a:end )
    call d.saveCurrentStat()
    return rc
endfunction 
fun! XPMautoUpdate(msg) 
    if !exists( 'b:_xpmark' )
        return ''
    endif
    let d = s:bufData()
    let isInsertMode = (d.lastMode == 'i' && mode() == 'i')
    if d.updateStrategy == 'manual' 
                \ || d.updateStrategy == 'normalMode' && isInsertMode
                \ || d.updateStrategy == 'insertMode' && !isInsertMode
        return ''
    endif
    call XPMupdate('auto')
    return ''
endfunction 
fun! XPMupdate(...) 
    if !exists( 'b:_xpmark' )
        return ''
    endif
    let d = s:bufData()
    let needUpdate = d.isUpdateNeeded()
    if !needUpdate
        call d.snapshot()
        call d.saveCurrentStat()
        return g:XPM_RET.no_updated_made
    endif
    call d.initCurrentStat()
    if d.lastMode =~ s:insertPattern && d.stat.mode =~ s:insertPattern
        let rc = d.insertModeUpdate()
    else
        let rc = d.normalModeUpdate()
    endif
    call d.saveCurrentStat()
    return rc
endfunction 
fun! XPMupdateStat() 
    let d = s:bufData()
    call d.saveCurrentStat()
endfunction 
fun! XPMupdateCursorStat(...) 
    let d = s:bufData()
    call d.saveCurrentCursorStat()
endfunction 
fun! XPMsetBufSortFunction( funcRef ) 
    let b:_xpm_compare = a:funcRef
endfunction 
fun! XPMallMark() 
    let d = s:bufData()
    let msg = ''
    let i = 0
    for name in d.orderedMarks
        let msg .= i . ' ' . name . repeat( '-', 30-len( name ) ) . " : " . substitute( string( d.marks[ name ] ), '\<\d\>', ' &', 'g' ) . "\n"
        let i += 1
    endfor
    return msg
endfunction 
fun! s:isUpdateNeeded() dict 
    if empty( self.marks ) && changenr() == self.lastChangenr
        return 0
    endif
    return 1
endfunction 
fun! s:initCurrentStat() dict 
    let self.stat = {
                \    'currentPosition'  : [ line( '.' ), col( '.' ) ],
                \    'totalLine'        : line( "$" ),
                \    'currentLineLength': len( getline( "." ) ),
                \    'mode'             : mode(),
                \    'positionOfMarkP'  : [ line( "'" . g:xpm_mark ), col( "'" . g:xpm_mark ) ] 
                \}
endfunction 
fun! s:snapshot() dict 
    let nr = changenr()
    if nr == self.lastChangenr
        return
    endif
    let n = self.lastChangenr + 1
    if !has_key( self.markHistory, n-1 )
        if has_key( self.markHistory, n-2 )
            let self.markHistory[ n-1 ] = self.markHistory[ n-2 ]
        else
            let self.markHistory[ n-1 ] = {'list':[], 'dict' :{}}
        endif
    endif
    Assert has_key( self.markHistory, n-1 )
    while n < nr
        let self.markHistory[ n ] = self.markHistory[ n - 1 ]
        if has_key( self.markHistory,  n - g:xpm_changenr_level )
            unlet self.markHistory[ n - g:xpm_changenr_level ]
        endif
        let n += 1
    endwhile
    let self.marks = copy( self.marks )
    let self.orderedMarks = copy( self.orderedMarks )
    let self.markHistory[ nr ] = { 'dict' : self.marks, 'list': self.orderedMarks }
endfunction 
fun! s:handleUndoRedo() dict 
    let nr = changenr()
    if nr < self.lastChangenr
        if has_key( self.markHistory, nr )
            let self.marks = self.markHistory[ nr ].dict
            let self.orderedMarks = self.markHistory[ nr ].list
        else
            call s:log.Info( 'u : no ' . nr . ' in markHistory, create new mark set' )
            let self.marks = {}
            let self.orderedMarks = []
        endif
        return 1
    elseif nr > self.lastChangenr && nr <= self.changenrRange[1]
        if has_key( self.markHistory, nr )
            let self.marks = self.markHistory[ nr ].dict
            let self.orderedMarks = self.markHistory[ nr ].list
        else
            call s:log.Info( "<C-r> no " . nr . ' in markHistory, create new mark set' )
            let self.marks = {}
            let self.orderedMarks = []
        endif
        return 1
    else
        return 0
    endif
endfunction 
fun! s:insertModeUpdate() dict 
    if self.handleUndoRedo()
        return g:XPM_RET.undo_redo
    endif
    let stat = self.stat
    if changenr() != self.lastChangenr
        call self.snapshot()
    endif
    let lastPos = self.lastPositionAndLength[ : 1 ]
    let bLastPos = [ self.lastPositionAndLength[0] + stat.totalLine - self.lastTotalLine, 0 ]
    let bLastPos[1] = self.lastPositionAndLength[1] - self.lastPositionAndLength[2] + len( getline( bLastPos[0] ) )
    if bLastPos[0] * 10000 + bLastPos[1] >= lastPos[0] * 10000 + lastPos[1]
        return self.updateWithNewChangeRange( self.lastPositionAndLength[ :1 ], stat.currentPosition )
    else
        return self.updateWithNewChangeRange( stat.currentPosition, stat.currentPosition )
    endif
endfunction 
fun! s:normalModeUpdate() dict 
    let stat = self.stat
    let nr = changenr()
    if nr == self.lastChangenr
        return g:XPM_RET.no_updated_made
    endif
    if self.handleUndoRedo()
        return g:XPM_RET.undo_redo
    endif
    let cs = [ line( "'[" ), col( "'[" ) ]
    let ce = [ line( "']" ), col( "']" ) ]
    call self.snapshot()
    let diffOfLine = stat.totalLine - self.lastTotalLine
    if stat.mode =~ s:insertPattern
        if diffOfLine > 0
            if self.lastPositionAndLength[0] < stat.positionOfMarkP[0]
                call self.updateMarksAfterLine( self.lastPositionAndLength[0] - 1 )
            else
                call self.updateMarksAfterLine( stat.currentPosition[0] - 1 )
            endif
        elseif self.lastMode =~ 's' || self.lastMode == "\<C-s>"
            return self.updateWithNewChangeRange([ line( "'<" ), col( "'<" ) ], stat.currentPosition)
        else
            return self.updateWithNewChangeRange(stat.currentPosition, stat.currentPosition)
        endif
    elseif self.lastMode =~ s:insertPattern
    else
        let linewiseDeletion =  stat.positionOfMarkP[0] == 0
        let lineNrOfChangeEndInLastStat = ce[0] - diffOfLine
        if linewiseDeletion
            if cs == ce
                call self.updateForLinewiseDeletion(cs[0], lineNrOfChangeEndInLastStat)
                return g:XPM_RET.updated
            else
            endif
        elseif stat.positionOfMarkP[0] == line( "'" . g:xpm_mark_nextline ) 
                    \&& stat.totalLine < self.lastTotalLine
            let endPos = [ self.lastPositionAndLength[0], self.lastPositionAndLength[2] ]
            return self.updateWithNewChangeRange( endPos, endPos )
        elseif self.lastMode =~ '[vVsS]'
        elseif diffOfLine == -1
            let cs = [ self.lastPositionAndLength[0], self.lastPositionAndLength[2] + 1 ]
            let ce = [ self.lastPositionAndLength[0], self.lastPositionAndLength[2] + 2 ]
            call s:log.Error( 'any chance going here?' )
            return self.updateWithNewChangeRange( cs, ce )
        elseif cs == [1, 1] && ce == [ stat.totalLine, 1 ] 
                    \|| diffOfLine < -1
            call XPMflush()
            return g:XPM_RET.updated
        endif
        return self.updateWithNewChangeRange(cs, ce)
    endif
    return g:XPM_RET.updated
endfunction 
fun! s:updateMarksAfterLine(line) dict 
    let diffOfLine = self.stat.totalLine - self.lastTotalLine
    for [ n, v ] in items( self.marks )
        if v[0] > a:line
            let self.marks[ n ] = [ v[0] + diffOfLine, v[1], v[2], v[3] ]
        endif
    endfor
endfunction 
fun! s:updateForLinewiseDeletion( fromLine, toLine ) dict 
    for [n, mark] in items( self.marks )
        if mark[0] >= a:toLine
            let self.marks[ n ] = [ mark[0] + self.stat.totalLine - self.lastTotalLine, mark[1], mark[2], mark[3] ]
        elseif mark[0] >= a:fromLine && mark[0] < a:toLine
            call self.removeMark( n )
        endif
    endfor
endfunction 
fun! s:updateWithNewChangeRange( changeStart, changeEnd ) dict 
    let bChangeEnd = [ a:changeEnd[0] - self.stat.totalLine, 
                \ a:changeEnd[1] - len( getline( a:changeEnd[0] ) ) ]
    let likelyIndexes = self.findLikelyRange( a:changeStart, bChangeEnd )
    if likelyIndexes == [ -1, -1 ]
        let indexes = [0, len( self.orderedMarks )]
        call self.updateMarks( indexes, a:changeStart, a:changeEnd )
        return g:XPM_RET.updated
    else
        let len = len( self.orderedMarks )
        let i = likelyIndexes[0]
        let j = likelyIndexes[1]
        call self.updateMarksBefore( [0, i + 1], a:changeStart, a:changeEnd )
        call self.updateMarks( [i+1, j],   a:changeStart, a:changeEnd )
        let len2 = len( self.orderedMarks )
        let j += len2 - len
        call self.updateMarksAfter( [j, len2], a:changeStart, a:changeEnd )
        return g:XPM_RET.likely_matched
    endif
endfunction 
fun! s:updateMarksBefore( indexRange, changeStart, changeEnd ) dict 
    let lineLengthCS    = len( getline( a:changeStart[0] ) )
    let [ iStart, iEnd ] = [ a:indexRange[0] - 1, a:indexRange[1] - 1 ]
    while iStart < iEnd
        let iStart += 1
        let name = self.orderedMarks[ iStart ]
        let mark = self.marks[ name ]
        let bMark = [ mark[0] - self.lastTotalLine, mark[1] - mark[2] ]
        if mark[0] < a:changeStart[0] 
            continue
        elseif mark[0] == a:changeStart[0] && mark[1] - 1 < a:changeStart[1]
            let self.marks[ name ] = [ mark[0], mark[1], lineLengthCS, mark[3] ]
        else
            call s:log.Error( 'mark should be before, but it is after start of change' )
        endif
    endwhile
endfunction 
fun! s:updateMarksAfter( indexRange, changeStart, changeEnd ) dict 
    let bChangeEnd = [ a:changeEnd[0] - self.stat.totalLine, 
                \ a:changeEnd[1] - len( getline( a:changeEnd[0] ) ) ]
    let diffOfLine = self.stat.totalLine - self.lastTotalLine
    let lineLengthCS    = len( getline( a:changeStart[0] ) )
    let lineLengthCE    = len( getline( a:changeEnd[0] ) )
    let lineNrOfChangeEndInLastStat = a:changeEnd[0] - diffOfLine
    let [ iStart, iEnd ] = [ a:indexRange[0] - 1, a:indexRange[1] - 1 ]
    while iStart < iEnd
        let iStart += 1
        let name = self.orderedMarks[ iStart ]
        let mark = self.marks[ name ]
        let bMark = [ mark[0] - self.lastTotalLine, mark[1] - mark[2] ]
        if mark[0] > lineNrOfChangeEndInLastStat
            if diffOfLine == 0
                break
            endif
            let self.marks[ name ] = [ mark[0] + diffOfLine, mark[1], mark[2], mark[3] ]
        elseif bMark[0] == bChangeEnd[0] && bMark[1] >= bChangeEnd[1]
            let self.marks[ name ] = [ a:changeEnd[0], bMark[1] + lineLengthCE, lineLengthCE, mark[3] ]
        else
            call s:log.Error( 'mark should be After changes, but it is before them.' )
        endif
    endwhile
endfunction 
fun! s:updateMarks( indexRange, changeStart, changeEnd ) dict 
    let bChangeEnd = [ a:changeEnd[0] - self.stat.totalLine, 
                \ a:changeEnd[1] - len( getline( a:changeEnd[0] ) ) ]
    let diffOfLine = self.stat.totalLine - self.lastTotalLine
    let lineLengthCS    = len( getline( a:changeStart[0] ) )
    let lineLengthCE    = len( getline( a:changeEnd[0] ) )
    let lineNrOfChangeEndInLastStat = a:changeEnd[0] - diffOfLine
    let [ iStart, iEnd ] = [ a:indexRange[0] - 1, a:indexRange[1] - 1 ]
    while iStart < iEnd
        let iStart += 1
        let name = self.orderedMarks[ iStart ]
        let mark = self.marks[ name ]
        let bMark = [ mark[0] - self.lastTotalLine, mark[1] - mark[2] ]
        if mark[0] < a:changeStart[0] 
            continue
        elseif mark[0] > lineNrOfChangeEndInLastStat
            let self.marks[ name ] = [ mark[0] + diffOfLine, mark[1], mark[2], mark[3] ]
        elseif mark[ 0 : 1 ] == a:changeStart && bMark == bChangeEnd
            if mark[3] == 0
                let self.marks[ name ] = [ mark[0], mark[1], lineLengthCS, 0 ]
            else
                let self.marks[ name ] = [ a:changeEnd[0], bMark[1] + lineLengthCE, lineLengthCE, 1 ]
            endif
        elseif mark[0] == a:changeStart[0] && mark[1] - 1 < a:changeStart[1]
            let self.marks[ name ] = [ mark[0], mark[1], lineLengthCS, mark[3] ]
        elseif bMark[0] == bChangeEnd[0] && bMark[1] >= bChangeEnd[1]
            let self.marks[ name ] = [ a:changeEnd[0], bMark[1] + lineLengthCE, lineLengthCE, mark[3] ]
        else
            call self.removeMark( name )
            let iStart -= 1
            let iEnd -= 1
        endif
    endwhile
endfunction 
fun! XPMupdateWithMarkRangeChanging( startMark, endMark, changeStart, changeEnd ) 
    let d = s:bufData()
    call d.initCurrentStat()
    if changenr() != d.lastChangenr
        call d.snapshot()
    endif
    let startIndex = index( d.orderedMarks, a:startMark )
    Assert startIndex >= 0
    let endIndex = index( d.orderedMarks, a:endMark, startIndex + 1 )
    Assert endIndex >= 0
    call d.updateMarksAfter( [ endIndex, len( d.orderedMarks ) ], a:changeStart, a:changeEnd )
    let [ i, len ] = [ startIndex + 1 , endIndex  ]
    while i < len
        let len -= 1
        let mark = d.orderedMarks[ i ]
    endwhile
    let lineLength = len( getline( a:changeStart[0] ) )
    let [ i ] = [ startIndex + 1 ]
    while i > 0
        let i -= 1
        let mark = d.orderedMarks[ i ]
        if d.marks[ mark ][0] < a:changeStart[0]
            break
        else
            let d.marks[ mark ][2] = len( getline( d.marks[ mark ][0] ) )
        endif
    endwhile
    call d.saveCurrentStat()
endfunction 
fun! s:findLikelyRange(changeStart, bChangeEnd) dict 
    if self.changeLikelyBetween.start == ''
                \ || self.changeLikelyBetween.end == ''
        return [ -1, -1 ]
    endif
    let [ likelyStart, likelyEnd ] = [ self.marks[ self.changeLikelyBetween.start ], 
                \ self.marks[ self.changeLikelyBetween.end ] ]
    let bLikelyEnd = [ likelyEnd[0] - self.lastTotalLine, 
                \ likelyEnd[1] - likelyEnd[2] ]
    let nChangeStart = a:changeStart[0] * 10000 + a:changeStart[1]
    let nLikelyStart = likelyStart[0] * 10000 + likelyStart[1]
    let nbChangeEnd = a:bChangeEnd[0] * 10000 + a:bChangeEnd[1]
    let nbLikelyEnd = bLikelyEnd[0] * 10000 + bLikelyEnd[1]
    if nChangeStart >= nLikelyStart && nbChangeEnd <= nbLikelyEnd
        let re = []
        let [i, len] = [0, len( self.orderedMarks )]
        while i < len
            if self.orderedMarks[ i ] == self.changeLikelyBetween.start
                call add( re, i )
            elseif self.orderedMarks[ i ] == self.changeLikelyBetween.end
                call add( re, i )
                return re
            endif
            let i += 1
        endwhile
        call s:log.Error( string( self.changeLikelyBetween ) . ' : end mark is not found!' )
    else
        return [ -1, -1 ]
    endif
endfunction 
fun! s:saveCurrentCursorStat() dict 
    let p = [ line( '.' ), col( '.' ) ]
    if p != self.lastPositionAndLength[ : 1 ]
        let self.lastPositionAndLength = p + [ len( getline( "." ) ) ]
            exe 'k'.g:xpm_mark
            if p[0] < line( '$' )
                exe '+1k' . g:xpm_mark_nextline
            else
                exe 'delmarks ' . g:xpm_mark_nextline
            endif
    endif
    let self.lastMode = mode()
endfunction 
fun! s:saveCurrentStat() dict 
    call self.saveCurrentCursorStat()
    let self.lastChangenr = changenr()
    let self.changenrRange[0] =  min( [ self.lastChangenr, self.changenrRange[0] ] )
    let self.changenrRange[1] =  max( [ self.lastChangenr, self.changenrRange[1] ] )
    let self.lastTotalLine = line( "$" )
endfunction 
fun! s:removeMark(name) dict 
    if !has_key( self.marks, a:name )
        return
    endif
    if self.changeLikelyBetween.start == a:name 
                \ || self.changeLikelyBetween.end == a:name
        let self.changeLikelyBetween = { 'start' : '', 'end' : '' }
    endif
    call filter( self.orderedMarks, 'v:val != ' . string( a:name ) )
    call remove( self.marks, a:name )
endfunction 
fun! s:addMarkOrder( name ) dict 
    let markToAdd = self.marks[ a:name ]
    let nPos = markToAdd[0] * 10000 + markToAdd[1]
    let i = -1
    for n in self.orderedMarks
        let i += 1
        let mark = self.marks[ n ]
        let nMark = mark[0] * 10000 + mark[1]
        if nMark == nPos
            let cmp = self.compare( a:name, n )
            if cmp == 0
                throw 'XPM : overlapped mark:' . a:name . '=' . string(markToAdd) . ' and ' . n . '=' . string( mark ) 
            elseif cmp > 0
                continue
            else
                call insert( self.orderedMarks, a:name, i )
                return
            endif
        elseif nPos < nMark
            call insert( self.orderedMarks, a:name, i )
            return
        endif
    endfor
    call add ( self.orderedMarks, a:name )
endfunction 
fun! s:compare( a, b ) dict 
    if exists( 'b:_xpm_compare' )
        return b:_xpm_compare( self, a:a, a:b )
    else
        return s:defaultCompare( self, a:a, a:b )
    endif
endfunction 
fun! s:ClassPrototype(...) 
    let p = {}
    for name in a:000
        let p[ name ] = function( '<SNR>' . s:sid . name )
    endfor
    return p
endfunction 
let s:prototype =  s:ClassPrototype(
            \    'addMarkOrder',
            \    'compare',
            \    'findLikelyRange', 
            \    'handleUndoRedo',
            \    'initCurrentStat',
            \    'insertModeUpdate',
            \    'isUpdateNeeded',
            \    'normalModeUpdate',
            \    'removeMark',
            \    'saveCurrentCursorStat',
            \    'saveCurrentStat',
            \    'snapshot',
            \    'updateForLinewiseDeletion',
            \    'updateMarks', 
            \    'updateMarksAfter', 
            \    'updateMarksAfterLine',
            \    'updateMarksBefore', 
            \    'updateWithNewChangeRange',
            \)
fun! s:initBufData() 
    let nr = changenr()
    let b:_xpmark = { 
                \ 'updateStrategy'       : 'auto', 
                \ 'stat'                 : {},
                \ 'orderedMarks'         : [],
                \ 'marks'                : {},
                \ 'markHistory'          : {}, 
                \ 'changeLikelyBetween'  : { 'start' : '', 'end' : '' }, 
                \ 'lastMode'             : 'n',
                \ 'lastPositionAndLength': [ line( '.' ), col( '.' ), len( getline( '.' ) ) ],
                \ 'lastTotalLine'        : line( '$' ),
                \ 'lastChangenr'         : nr,
                \ 'changenrRange'        : [nr, nr], 
                \ }
    let b:_xpmark.markHistory[ nr ] = { 'dict' : b:_xpmark.marks, 'list' : b:_xpmark.orderedMarks }
    call extend( b:_xpmark, s:prototype, 'force' )
    exe 'k' . g:xpm_mark
    if line( '.' ) < line( '$' )
        exe '+1k' . g:xpm_mark_nextline
    else
        exe 'delmarks ' . g:xpm_mark_nextline
    endif
endfunction 
fun! s:bufData() 
    if !exists('b:_xpmark')
        call s:initBufData()
    endif
    return b:_xpmark
endfunction 
fun! s:defaultCompare(d, markA, markB) 
    let [ ma, mb ] = [ a:d.marks[ a:markA ], a:d.marks[ a:markB ] ]
    let nMarkA = ma[0] * 10000 + ma[1]
    let nMarkB = mb[0] * 10000 + mb[1]
    return (nMarkA - nMarkB) != 0 ? (nMarkA - nMarkB) : (a:d.marks[ a:markA ][3] - a:d.marks[ a:markB ][3])
endfunction 
if &ruler && &rulerformat == ""
    set rulerformat=%17(%<%f\ %h%m%r%=%-14.(%l,%c%V%)\ %P%)
elseif !&ruler
    set rulerformat=
endif
set ruler
let &rulerformat .= '%{XPMautoUpdate("ruler")}'
fun! PrintDebug()
    let d = s:bufData()
    let debugString  = changenr()
    let debugString .= ' p:' . string( getpos( "'" . g:xpm_mark )[ 1 : 2 ] )
    let debugString .= ' ' . string( [[ line( "'[" ), col( "'[" ) ], [ line( "']" ), col( "']" ) ]] ) . " "
    let debugString .= " " . mode() . string( [line( "." ), col( "." )] ) . ' last:' .string( d.lastPositionAndLength )
    return substitute( debugString, '\s', '' , 'g' )
endfunction
nnoremap ,m :call XPMhere('c', 'l')<cr>
nnoremap ,M :call XPMhere('c', 'r')<cr>
nnoremap ,g :call XPMgoto('c')<cr>
