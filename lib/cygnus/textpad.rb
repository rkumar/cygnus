#!/usr/bin/env ruby
# ----------------------------------------------------------------------------- #
#         File: textpad.rb
#  Description: A class that displays text using a pad.
#         The motivation for this is to put formatted text and not care about truncating and 
#         stuff. Also, there will be only one write, not each time scrolling happens.
#         I found textview code for repaint being more complex than required.
#       Author: rkumar http://github.com/rkumar/mancurses/
#         Date: 2011-11-09 - 16:59
#      License: Same as Ruby's License (http://www.ruby-lang.org/LICENSE.txt)
#  Last update: 2013-03-13 16:13
#
#  == CHANGES
#  == TODO 
#     _ in popup case allowing scrolling when it should not so you get an extra char at end
#     _ The list one needs a f-char like functionality.
#     x handle putting data again and overwriting existing
#       When reputting data, the underlying pad needs to be properly cleared
#       esp last row and last col
#
#     x add mappings and process key in handle_keys and other widget things
#     - can pad movement and other ops be abstracted into module for reuse
#     / get scrolling like in vim (C-f e y b d)
#
#   == TODO 2013-03-07 - 20:34 
#   _ key bindings not showing up -- bind properly
# ----------------------------------------------------------------------------- #
#
require 'rbcurse'
require 'rbcurse/core/include/bordertitle'

include RubyCurses
module Cygnus
  extend self
  class TextPad < Widget
    include BorderTitle

    dsl_accessor :suppress_border
    attr_reader :current_index
    # You may pass height, width, row and col for creating a window otherwise a fullscreen window
    # will be created. If you pass a window from caller then that window will be used.
    # Some keys are trapped, jkhl space, pgup, pgdown, end, home, t b
    # This is currently very minimal and was created to get me started to integrating
    # pads into other classes such as textview.
    def initialize form=nil, config={}, &block

      @editable = false
      @focusable = true
      @config = config
      @row = @col = 0
      @prow = @pcol = 0
      @startrow = 0
      @startcol = 0
      @list = []
      super

      #@height = @height.ifzero(FFI::NCurses.LINES)
      #@width = @width.ifzero(FFI::NCurses.COLS)
      @rows = @height
      @cols = @width
      # NOTE XXX if cols is > COLS then padrefresh can fail
      @startrow = @row
      @startcol = @col
      #@suppress_border = config[:suppress_border]
      @row_offset = @col_offset = 1
      unless @suppress_border
        @startrow += 1
        @startcol += 1
        @rows -=3  # 3 is since print_border_only reduces one from width, to check whether this is correct
        @cols -=3
      end
      @row_offset = @col_offset = 0 if @suppress_borders
      @top = @row
      @left = @col
      @lastrow = @row + 1
      @lastcol = @col + 1
      @_events << :PRESS
      @_events << :ENTER_ROW
      @scrollatrows = @height - 3
      init_vars
    end
    def init_vars
      $multiplier = 0
      @oldindex = @current_index = 0
      # column cursor
      @prow = @pcol = @curpos = 0
      if @row && @col
        @lastrow = @row + 1
        @lastcol = @col + 1
      end
      @repaint_required = true
    end
    def rowcol #:nodoc:
      return @row+@row_offset, @col+@col_offset
    end

    private
    ## XXX in list text returns the selected row, list returns the full thing, keep consistent
    def create_pad
      destroy if @pad
      #@pad = FFI::NCurses.newpad(@content_rows, @content_cols)
      @pad = @window.get_pad(@content_rows, @content_cols )
    end

    private
    # create and populate pad
    def populate_pad
      @_populate_needed = false
      # how can we make this more sensible ? FIXME
      #@renderer ||= DefaultFileRenderer.new #if ".rb" == @filetype
      @content_rows = @content.count
      @content_cols = content_cols()
      # this should be explicit and not "intelligent"
      #@title += " [ #{@content_rows},#{@content_cols}] " if @cols > 50
      @content_rows = @rows if @content_rows < @rows
      @content_cols = @cols if @content_cols < @cols
      #$log.debug "XXXX content_cols = #{@content_cols}"

      create_pad

      # clearstring is the string required to clear the pad to backgroud color
      @clearstring = nil
      cp = get_color($datacolor, @color, @bgcolor)
      @cp = FFI::NCurses.COLOR_PAIR(cp)
      if cp != $datacolor
        @clearstring ||= " " * @width
      end

      Ncurses::Panel.update_panels
      @content.each_index { |ix|
        #FFI::NCurses.mvwaddstr(@pad,ix, 0, @content[ix])
        render @pad, ix, @content[ix]
      }

    end

    public
    # supply a custom renderer that implements +render()+
    # @see render
    def renderer r
      @renderer = r
    end
    #
    # default method for rendering a line
    #
    def render pad, lineno, text
      if text.is_a? Chunks::ChunkLine
        FFI::NCurses.wmove @pad, lineno, 0
        a = get_attrib @attrib
      
        show_colored_chunks text, nil, a
        return
      end
      if @renderer
        @renderer.render @pad, lineno, text
      else
        ## messabox does have a method to paint the whole window in bg color its in rwidget.rb
        att = NORMAL
        FFI::NCurses.wattron(@pad, @cp | att)
        FFI::NCurses.mvwaddstr(@pad,lineno, 0, @clearstring) if @clearstring
        FFI::NCurses.mvwaddstr(@pad,lineno, 0, @content[lineno])

        #FFI::NCurses.mvwaddstr(pad, lineno, 0, text)
        FFI::NCurses.wattroff(@pad, @cp | att)
      end
    end

    # supply a filename as source for textpad
    # Reads up file into @content

    def filename(filename)
      @file = filename
      unless File.exists? filename
        alert "#{filename} does not exist"
        return
      end
      @filetype = File.extname filename
      @content = File.open(filename,"r").readlines
      if @filetype == ""
        if @content.first.index("ruby")
          @filetype = ".rb"
        end
      end
      init_vars
      @repaint_all = true
      @_populate_needed = true
    end

    # Supply an array of string to be displayed
    # This will replace existing text

    ## XXX in list text returns the selected row, list returns the full thing, keep consistent
    def text lines
      raise "text() receiving null content" unless lines
      @content = lines
      @_populate_needed = true
      @repaint_all = true
      init_vars
    end
    alias :list :text
    def content
      raise "content is nil " unless @content
      return @content
    end

    ## ---- the next 2 methods deal with printing chunks
    # we should put it int a common module and include it
    # in Window and Pad stuff and perhaps include it conditionally.

    ## 2013-03-07 - 19:57 changed width to @content_cols since data not printing
    # in some cases fully when ansi sequences were present int some line but not in others
    # lines without ansi were printing less by a few chars.
    # This was prolly copied from rwindow, where it is okay since its for a specific width
    def print(string, _width = @content_cols)
      #return unless visible?
      w = _width == 0? Ncurses.COLS : _width
      FFI::NCurses.waddnstr(@pad,string.to_s, w) # changed 2011 dts  
    end

    def show_colored_chunks(chunks, defcolor = nil, defattr = nil)
      #return unless visible?
      chunks.each do |chunk| #|color, chunk, attrib|
        case chunk
        when Chunks::Chunk
          color = chunk.color
          attrib = chunk.attrib
          text = chunk.text
        when Array
          # for earlier demos that used an array
          color = chunk[0]
          attrib = chunk[2]
          text = chunk[1]
        end

        color ||= defcolor
        attrib ||= defattr || NORMAL

        #cc, bg = ColorMap.get_colors_for_pair color
        #$log.debug "XXX: CHUNK textpad #{text}, cp #{color} ,  attrib #{attrib}. #{cc}, #{bg} "
        FFI::NCurses.wcolor_set(@pad, color,nil) if color
        FFI::NCurses.wattron(@pad, attrib) if attrib
        print(text)
        FFI::NCurses.wattroff(@pad, attrib) if attrib
      end
    end

    def formatted_text text, fmt
      require 'rbcurse/core/include/chunk'
      @formatted_text = text
      @color_parser = fmt
      @repaint_required = true
      # don't know if start is always required. so putting in caller
      #goto_start
      #remove_all
    end

    # write pad onto window
    #private
    def padrefresh
      top = @window.top
      left = @window.left
      sr = @startrow + top
      sc = @startcol + left
      retval = FFI::NCurses.prefresh(@pad,@prow,@pcol, sr , sc , @rows + sr , @cols+ sc );
      $log.warn "XXX:  PADREFRESH #{retval}, #{@prow}, #{@pcol}, #{sr}, #{sc}, #{@rows+sr}, #{@cols+sc}." if retval == -1
      # padrefresh can fail if width is greater than NCurses.COLS
      #FFI::NCurses.prefresh(@pad,@prow,@pcol, @startrow + top, @startcol + left, @rows + @startrow + top, @cols+@startcol + left);
    end

    # convenience method to return byte
    private
    def key x
      x.getbyte(0)
    end

    # length of longest string in array
    # This will give a 'wrong' max length if the array has ansi color escape sequences in it
    # which inc the length but won't be printed. Such lines actually have less length when printed
    # So in such cases, give more space to the pad.
    def content_cols
      longest = @content.max_by(&:length)
      ## 2013-03-06 - 20:41 crashes here for some reason when man gives error message no man entry
      return 0 unless longest
      longest.length
    end

    public
    def repaint
      ## 2013-03-08 - 21:01 This is the fix to the issue of form callign an event like ? or F1
      # which throws up a messagebox which leaves a black rect. We have no place to put a refresh
      # However, form does call repaint for all objects, so we can do a padref here. Otherwise,
      # it would get rejected. UNfortunately this may happen more often we want, but we never know
      # when something pops up on the screen.
      padrefresh unless @repaint_required
      return unless @repaint_required
      if @formatted_text
        $log.debug "XXX:  INSIDE FORMATTED TEXT "

        l = RubyCurses::Utils.parse_formatted_text(@color_parser,
                                               @formatted_text)

        text(l)
        @formatted_text = nil
      end

      ## moved this line up or else create_p was crashing
      @window ||= @graphic
      populate_pad if @_populate_needed
      #HERE we need to populate once so user can pass a renderer
      unless @suppress_border
        if @repaint_all
          ## XXX im not getting the background color.
          #@window.print_border_only @top, @left, @height-1, @width, $datacolor
          clr = get_color $datacolor, @color, @bgcolor
          #@window.print_border @top, @left, @height-1, @width, clr
          @window.print_border_only @top, @left, @height-1, @width, clr
          print_title
          @window.wrefresh
        end
      end

      padrefresh
      Ncurses::Panel.update_panels
      @repaint_required = false
      @repaint_all = false
    end

    #
    # key mappings
    #
    def map_keys
      @mapped_keys = true
      bind_key([?g,?g], 'goto_start'){ goto_start } # mapping double keys like vim
      bind_key(279, 'goto_start'){ goto_start } 
      bind_keys([?G,277], 'goto end'){ goto_end } 
      bind_keys([?k,KEY_UP], "Up"){ up } 
      bind_keys([?j,KEY_DOWN], "Down"){ down } 
      bind_key(?\C-e, "Scroll Window Down"){ scroll_window_down } 
      bind_key(?\C-y, "Scroll Window Up"){ scroll_window_up } 
      bind_keys([32,338, ?\C-d], "Scroll Forward"){ scroll_forward } 
      bind_keys([?\C-b,339]){ scroll_backward } 
      # the next one invalidates the single-quote binding for bookmarks
      #bind_key([?',?']){ goto_last_position } # vim , goto last row position (not column)
      bind_key(?/, :ask_search)
      bind_key(?n, :find_more)
      bind_key([?\C-x, ?>], :scroll_right)
      bind_key([?\C-x, ?<], :scroll_left)
      bind_key(?\M-l, :scroll_right)
      bind_key(?\M-h, :scroll_left)
      bind_key(?L, :bottom_of_window)
      bind_key(?M, :middle_of_window)
      bind_key(?H, :top_of_window)
      bind_key(?w, :forward_word)
      bind_key(KEY_ENTER, :fire_action_event)
    end

    # goto first line of file
    def goto_start
      #@oldindex = @current_index
      $multiplier ||= 0
      if $multiplier > 0
        goto_line $multiplier - 1
        return
      end
      @current_index = 0
      @curpos = @pcol = @prow = 0
      @prow = 0
      $multiplier = 0
    end

    # goto last line of file
    def goto_end
      #@oldindex = @current_index
      $multiplier ||= 0
      if $multiplier > 0
        goto_line $multiplier - 1
        return
      end
      @current_index = @content.count() - 1
      @prow = @current_index - @scrollatrows
      $multiplier = 0
    end
    def goto_line line
      ## we may need to calculate page, zfm style and place at right position for ensure visible
      #line -= 1
      @current_index = line
      ensure_visible line
      bounds_check
      $multiplier = 0
    end
    def top_of_window
      @current_index = @prow 
      $multiplier ||= 0
      if $multiplier > 0
        @current_index += $multiplier
        $multiplier = 0
      end
    end
    def bottom_of_window
      @current_index = @prow + @scrollatrows
      $multiplier ||= 0
      if $multiplier > 0
        @current_index -= $multiplier
        $multiplier = 0
      end
    end
    def middle_of_window
      @current_index = @prow + (@scrollatrows/2)
      $multiplier = 0
    end

    # move down a line mimicking vim's j key
    # @param [int] multiplier entered prior to invoking key
    def down num=(($multiplier.nil? or $multiplier == 0) ? 1 : $multiplier)
      #@oldindex = @current_index if num > 10
      @current_index += num
      ensure_visible
      $multiplier = 0
    end

    # move up a line mimicking vim's k key
    # @param [int] multiplier entered prior to invoking key
    def up num=(($multiplier.nil? or $multiplier == 0) ? 1 : $multiplier)
      #@oldindex = @current_index if num > 10
      @current_index -= num
      #unless is_visible? @current_index
        #if @prow > @current_index
          ##$status_message.value = "1 #{@prow} > #{@current_index} "
          #@prow -= 1
        #else
        #end
      #end
      $multiplier = 0
    end

    # scrolls window down mimicking vim C-e
    # @param [int] multiplier entered prior to invoking key
    def scroll_window_down num=(($multiplier.nil? or $multiplier == 0) ? 1 : $multiplier)
      @prow += num
        if @prow > @current_index
          @current_index += 1
        end
      #check_prow
      $multiplier = 0
    end

    # scrolls window up mimicking vim C-y
    # @param [int] multiplier entered prior to invoking key
    def scroll_window_up num=(($multiplier.nil? or $multiplier == 0) ? 1 : $multiplier)
      @prow -= num
      unless is_visible? @current_index
        # one more check may be needed here TODO
        @current_index -= num
      end
      $multiplier = 0
    end

    # scrolls lines a window full at a time, on pressing ENTER or C-d or pagedown
    def scroll_forward
      #@oldindex = @current_index
      @current_index += @scrollatrows
      @prow = @current_index - @scrollatrows
    end

    # scrolls lines backward a window full at a time, on pressing pageup 
    # C-u may not work since it is trapped by form earlier. Need to fix
    def scroll_backward
      #@oldindex = @current_index
      @current_index -= @scrollatrows
      @prow = @current_index - @scrollatrows
    end
    def goto_last_position
      return unless @oldindex
      tmp = @current_index
      @current_index = @oldindex
      @oldindex = tmp
      bounds_check
    end
    def scroll_right
      # I don't think it will ever be less since we've increased it to cols
      if @content_cols <= @cols
        maxpcol = 0
        @pcol = 0
      else
        maxpcol = @content_cols - @cols - 1
        @pcol += 1
        @pcol = maxpcol if @pcol > maxpcol
      end
      # to prevent right from retaining earlier painted values
      # padreader does not do a clear, yet works fine.
      # OK it has an update_panel after padrefresh, that clears it seems.
      #this clears entire window not just the pad
      #FFI::NCurses.wclear(@window.get_window)
      # so border and title is repainted after window clearing
      #
      # Next line was causing all sorts of problems when scrolling  with ansi formatted text
      #@repaint_all = true
    end
    def scroll_left
      @pcol -= 1
    end
    #
    #
    #
    # NOTE : if advancing pcol one has to clear the pad or something or else 
    # there'll be older content on the right side.
    #
    def handle_key ch
      return :UNHANDLED unless @content
      map_keys unless @mapped_keys

      @maxrow = @content_rows - @rows
      @maxcol = @content_cols - @cols 

      # need to understand the above line, can go below zero.
      # all this seems to work fine in padreader.rb in util.
      # somehow maxcol going to -33
      @oldrow = @prow
      @oldcol = @pcol
      $log.debug "XXX: PAD got #{ch} prow = #{@prow}"
      begin
        case ch
        when key(?l)
          # TODO take multipler
          #@pcol += 1
          if @curpos < @cols
            @curpos += 1
          end
        when key(?$)
          #@pcol = @maxcol - 1
          @curpos = [@content[@current_index].size, @cols].min
        when key(?h)
          # TODO take multipler
          if @curpos > 0
            @curpos -= 1
          end
        #when key(?0)
          #@curpos = 0
      when ?0.getbyte(0)..?9.getbyte(0)
        if ch == ?0.getbyte(0) && $multiplier == 0
          # copy of C-a - start of line
          @repaint_required = true if @pcol > 0 # tried other things but did not work
          @pcol = 0
          @curpos = 0
          return 0
        end
        # storing digits entered so we can multiply motion actions
        $multiplier *= 10 ; $multiplier += (ch-48)
        return 0
        when ?\C-c.getbyte(0)
          $multiplier = 0
          return 0
        else
          # check for bindings, these cannot override above keys since placed at end
          begin
            ret = process_key ch, self
            $multiplier = 0
            bounds_check
            ## If i press C-x > i get an alert from rwidgets which blacks the screen
            # if i put a padrefresh here it becomes okay but only for one pad,
            # i still need to do it for all pads.
          rescue => err
            $log.error " TEXTPAD ERROR INS #{err} "
            $log.debug(err.backtrace.join("\n"))
            textdialog ["Error in TextPad: #{err} ", *err.backtrace], :title => "Exception"
          end
          ## NOTE if textpad does not handle the event and it goes to form which pops
          # up a messagebox, then padrefresh does not happen, since control does not 
          # come back here, so a black rect is left on screen
          # please note that a bounds check will not happen for stuff that 
          # is triggered by form, so you'll have to to it yourself or 
          # call setrowcol explicity if the cursor is not updated
          return :UNHANDLED if ret == :UNHANDLED
        end
      rescue => err
        $log.error " TEXTPAD ERROR 111 #{err} "
        $log.debug( err) if err
        $log.debug(err.backtrace.join("\n")) if err
        textdialog ["Error in TextPad: #{err} ", *err.backtrace], :title => "Exception"
        $error_message.value = ""
      ensure
        padrefresh
        Ncurses::Panel.update_panels
      end
      return 0
    end # while loop
    def fire_action_event
      return if @content.nil? || @content.size == 0
      require 'rbcurse/core/include/ractionevent'
      aev = TextActionEvent.new self, :PRESS, current_value().to_s, @current_index, @curpos
      fire_handler :PRESS, aev
    end
    def current_value
      @content[@current_index]
    end
    # 
    def on_enter_row arow
      return if @content.nil? || @content.size == 0
      require 'rbcurse/core/include/ractionevent'
      aev = TextActionEvent.new self, :ENTER_ROW, current_value().to_s, @current_index, @curpos
      fire_handler :ENTER_ROW, aev
      @repaint_required = true
    end

    # destroy the pad, this needs to be called from somewhere, like when the app
    # closes or the current window closes , or else we could have a seg fault
    # or some ugliness on the screen below this one (if nested).

    # Now since we use get_pad from window, upon the window being destroyed,
    # it will call this. Else it will destroy pad
    def destroy
      FFI::NCurses.delwin(@pad) if @pad # when do i do this ? FIXME
      @pad = nil
    end
    def is_visible? index
      j = index - @prow #@toprow
      j >= 0 && j <= @scrollatrows
    end
    def on_enter
      set_form_row
    end
    def set_form_row
      setrowcol @lastrow, @lastcol
    end
    def set_form_col
    end

    private
    
    # check that current_index and prow are within correct ranges
    # sets row (and someday col too)
    # sets repaint_required

    def bounds_check
      r,c = rowcol
      @current_index = 0 if @current_index < 0
      @current_index = @content.count()-1 if @current_index > @content.count()-1
      ensure_visible

      #$status_message.value = "visible #{@prow} , #{@current_index} "
      #unless is_visible? @current_index
        #if @prow > @current_index
          ##$status_message.value = "1 #{@prow} > #{@current_index} "
          #@prow -= 1
        #else
        #end
      #end
      #end
      check_prow
      #$log.debug "XXX: PAD BOUNDS ci:#{@current_index} , old #{@oldrow},pr #{@prow}, max #{@maxrow} pcol #{@pcol} maxcol #{@maxcol}"
      @crow = @current_index + r - @prow
      @crow = r if @crow < r
      # 2 depends on whetehr suppressborders
      @crow = @row + @height -2 if @crow >= r + @height -2
      setrowcol @crow, @curpos+c
      lastcurpos @crow, @curpos+c
      if @oldindex != @current_index
        on_enter_row @current_index
        @oldindex = @current_index
      end
      if @oldrow != @prow || @oldcol != @pcol
        # only if scrolling has happened.
        @repaint_required = true
      end
    end
    def lastcurpos r,c
      @lastrow = r
      @lastcol = c
    end


  # check that prow and pcol are within bounds

    def check_prow
      @prow = 0 if @prow < 0
      @pcol = 0 if @pcol < 0

      cc = @content.count

      if cc < @rows
        @prow = 0
      else
        maxrow = cc - @rows - 1
        if @prow > maxrow
          @prow = maxrow
        end
      end
      # we still need to check the max that prow can go otherwise
      # the pad shows earlier stuff.
      # 
      return
      # the following was causing bugs if content was smaller than pad
      if @prow > @maxrow-1
        @prow = @maxrow-1
      end
      if @pcol > @maxcol-1
        @pcol = @maxcol-1
      end
    end
    public
    ## 
    # Ask user for string to search for
    def ask_search
      str = get_string("Enter pattern: ")
      return if str.nil? 
      str = @last_regex if str == ""
      return if str == ""
      ix = next_match str
      return unless ix
      @last_regex = str

      #@oldindex = @current_index
      @current_index = ix[0]
      @curpos = ix[1]
      ensure_visible
    end
    ## 
    # Find next matching row for string accepted in ask_search
    #
    def find_more
      return unless @last_regex
      ix = next_match @last_regex
      return unless ix
      #@oldindex = @current_index
      @current_index = ix[0]
      @curpos = ix[1]
      ensure_visible
    end

    ## 
    # Find the next row that contains given string
    # @return row and col offset of match, or nil
    # @param String to find
    def next_match str
      first = nil
      ## content can be string or Chunkline, so we had to write <tt>index</tt> for this.
      ## =~ does not give an error, but it does not work.
      @content.each_with_index do |line, ix|
        col = line.index str
        if col
          first ||= [ ix, col ]
          if ix > @current_index
            return [ix, col]
          end
        end
      end
      return first
    end
    ## 
    # Ensure current row is visible, if not make it first row
    # NOTE - need to check if its at end and then reduce scroll at rows, check_prow does that
    # 
    # @param current_index (default if not given)
    #
    def ensure_visible row = @current_index
      unless is_visible? row
          @prow = @current_index
      end
    end
    def forward_word
      $multiplier = 1 if !$multiplier || $multiplier == 0
      line = @current_index
      buff = @content[line].to_s
      return unless buff
      pos = @curpos || 0 # list does not have curpos
      $multiplier.times {
        found = buff.index(/[[:punct:][:space:]]\w/, pos)
        if !found
          # if not found, we've lost a counter
          if line+1 < @content.length
            line += 1
          else
            return
          end
          pos = 0
        else
          pos = found + 1
        end
        $log.debug " forward_word: pos #{pos} line #{line} buff: #{buff}"
      }
      $multiplier = 0
      @current_index = line
      @curpos = pos
      ensure_visible
      #@buffer = @list[@current_index].to_s
      #set_form_row
      #set_form_col pos
      @repaint_required = true
    end

  end  # class textpad

  # a test renderer to see how things go
  class DefaultFileRenderer
    def render pad, lineno, text
      bg = :black
      fg = :white
      att = NORMAL
      #cp = $datacolor
      cp = get_color($datacolor, fg, bg)
      if text =~ /^\s*# / || text =~ /^\s*## /
        fg = :red
        #att = BOLD
        cp = get_color($datacolor, fg, bg)
      elsif text =~ /^\s*#/
        fg = :blue
        cp = get_color($datacolor, fg, bg)
      elsif text =~ /^\s*(class|module) /
        fg = :cyan
        att = BOLD
        cp = get_color($datacolor, fg, bg)
      elsif text =~ /^\s*def / || text =~ /^\s*function /
        fg = :yellow
        att = BOLD
        cp = get_color($datacolor, fg, bg)
      elsif text =~ /^\s*(end|if |elsif|else|begin|rescue|ensure|include|extend|while|unless|case |when )/
        fg = :magenta
        att = BOLD
        cp = get_color($datacolor, fg, bg)
      elsif text =~ /^\s*=/
        # rdoc case
        fg = :blue
        bg = :white
        cp = get_color($datacolor, fg, bg)
        att = REVERSE
      end
      FFI::NCurses.wattron(pad,FFI::NCurses.COLOR_PAIR(cp) | att)
      FFI::NCurses.mvwaddstr(pad, lineno, 0, text)
      FFI::NCurses.wattroff(pad,FFI::NCurses.COLOR_PAIR(cp) | att)

    end
  end
end
