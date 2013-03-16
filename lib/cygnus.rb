require "cygnus/version"

module Cygnus
  # Your code goes here...
  # mmm what code ?
# http://www.ruby-doc.org/stdlib-1.9.3/libdoc/shellwords/rdoc/Shellwords.html
require 'shellwords'
require 'fileutils'
CONFIG_FILE="~/.lyrainfo"


$selected_files = Array.new
$bookmarks = {}
$mode = nil
$glines=%x(tput lines).to_i
$gcols=%x(tput cols).to_i
# grows depends on size of textpad @cols, not screen size, since this is no longer cli
$grows = $glines - 2
$pagesize = 60
$gviscols = 3
$pagesize = $grows * $gviscols
$stact = 0
$editor_mode = true
$enhanced_mode = true
$visual_block_start = nil
$pager_command = {
  :text => 'most',
  :image => 'open',
  :zip => 'tar ztvf %% | most',
  :unknown => 'open'
}
$dir_position = {}
## CONSTANTS
GMARK='*'
CURMARK='>'
MSCROLL = 10
SPACE=" "
#CLEAR      = "\e[0m"
#BOLD       = "\e[1m"
#BOLD_OFF       = "\e[22m"
#RED        = "\e[31m"
#ON_RED        = "\e[41m"
#GREEN      = "\e[32m"
#YELLOW     = "\e[33m"
#BLUE       = "\e[1;34m"
#
ON_BLUE    = "\e[44m"
#REVERSE    = "\e[7m"
CURSOR_COLOR = ""
CLEAR = ""
$patt=nil
$ignorecase = true
$quitting = false
$modified = $writing = false
$visited_files = []
## dir stack for popping
$visited_dirs = []
## dirs where some work has been done, for saving and restoring
$used_dirs = []
$default_sort_order = "om"
$sorto = $default_sort_order
$viewctr = 0
$history = []
$sta = $cursor = 0
$visual_mode = false

  ## main loop which calls all other programs

## code related to long listing of files
GIGA_SIZE = 1073741824.0
MEGA_SIZE = 1048576.0
KILO_SIZE = 1024.0

# Return the file size with a readable style.
def readable_file_size(size, precision)
  case
    #when size == 1 : "1 B"
  when size < KILO_SIZE then "%d B" % size
  when size < MEGA_SIZE then "%.#{precision}f K" % (size / KILO_SIZE)
  when size < GIGA_SIZE then "%.#{precision}f M" % (size / MEGA_SIZE)
  else "%.#{precision}f G" % (size / GIGA_SIZE)
  end
end
## format date for file given stat
def date_format t
  t.strftime "%Y/%m/%d"
end
## 
#
# print in columns
# ary - array of data
# sz  - lines in one column
#
def columnate_with_indexing ary, sz
  buff=Array.new
  $log.warn "columnate_with_indexing got nil list " unless ary
  return buff if ary.nil? || ary.size == 0
  
  # determine width based on number of files to show
  # if less than sz then 1 col and full width
  #
  wid = 30
  ars = ary.size
  ars = [$pagesize, ary.size].min
  # 2 maybe for borders also
  d = 0
  if ars <= sz
    wid = $gcols - d
  else
    tmp = (ars * 1.000/ sz).ceil
    wid = $gcols / tmp - d
  end

  # ix refers to the index in the complete file list, wherease we only show 60 at a time
  ix=0
  while true
    ## ctr refers to the index in the column
    ctr=0
    while ctr < sz

      cur=SPACE
      cur = CURMARK if ix + $sta == $cursor
      f = ary[ix]
      # be careful of modifying f or original array gets modified XXX
      k = get_shortcut ix
      isdir = f[-1] == "/"
      fsz = f.size + k.to_s.size + 0
      fsz = f.size + 1
      if fsz > wid
        # truncated since longer
        f = f[0, wid-2]+"$ "
        ## we do the coloring after trunc so ANSI escpe seq does not get get
        #if ix + $sta == $cursor
          #f = "#{CURSOR_COLOR}#{f}#{CLEAR}"
        #end
      else
        ## we do the coloring before padding so the entire line does not get padded, only file name
        #if ix + $sta == $cursor
          #f = "#{CURSOR_COLOR}#{f}#{CLEAR}"
        #end
        f = f.ljust(wid)
        # pad with spaces
        #f << " " * (wid-fsz)
        #f = f + " " * (wid-fsz)
      end
      # now we add the shortcut with the coloring (we need to adjust the space of the shortcut)
      #
      colr = "white"
      colr = "blue, bold" if isdir
      # this directly modified the damned index resulting in searches failing
      #k << " " if k.length == 1
      k = k + " " if k.length == 1

      f = "#{cur}#[fg=yellow, bold]#{k}#[end] #[fg=#{colr}]#{f}#[end]" 

      if buff[ctr]
        buff[ctr] += f
      else
        buff[ctr] = f
      end

      ctr+=1
      ix+=1
      break if ix >= ary.size
    end
    break if ix >= ary.size
  end
  return buff
end
## formats the data with number, mark and details 
def format ary
  #buff = Array.new
  buff = Array.new(ary.size)
  return buff if ary.nil? || ary.size == 0

  # determine width based on number of files to show
  # if less than sz then 1 col and full width
  #
  # ix refers to the index in the complete file list, wherease we only show 60 at a time
  ix=0
  ctr=0
  ary.each do |f|
    ## ctr refers to the index in the column
    ind = get_shortcut(ix)
    mark=SPACE
    cur=SPACE
    cur = CURMARK if ix + $sta == $cursor
    mark=GMARK if $selected_files.index(ary[ix])

    if $long_listing
      begin
        unless File.exist? f
          last = f[-1]
          if last == " " || last == "@" || last == '*'
            stat = File.stat(f.chop)
          end
        else
          stat = File.stat(f)
        end
        f = "%10s  %s  %s" % [readable_file_size(stat.size,1), date_format(stat.mtime), f]
      rescue Exception => e
        f = "%10s  %s  %s" % ["?", "??????????", f]
      end
    end

    s = "#{ind}#{mark}#{cur}#{f}"
    # I cannot color the current line since format does the chopping
    # so not only does the next lines alignment get skeweed, but also if the line is truncated
    # then the color overflows.
    #if ix + $sta == $cursor
      #s = "#{RED}#{s}#{CLEAR}"
    #end

    buff[ctr] = s

    ctr+=1
    ix+=1
  end
  return buff
end
## select file based on key pressed
def select_hint view, ch
  # a to y is direct
  # if x or z take a key IF there are those many
  #
  ix = get_index(ch, view.size)
  if ix
    f = view[ix]
    return unless f
    $cursor = $sta + ix

    if $mode == 'SEL'
      toggle_select f
    elsif $mode == 'COM'
      run_command f
    else
      open_file f
    end
    #selectedix=ix
  end
end
## toggle selection state of file
def toggle_select f
  if $selected_files.index f
    $selected_files.delete f
  else
    $selected_files.push f
  end
end
## open file or directory
def TODOopen_file f
  return unless f
  if f[0] == "~"
    f = File.expand_path(f)
  end
  unless File.exist? f
    # this happens if we use (T) in place of (M) 
    # it places a space after normal files and @ and * which borks commands
    last = f[-1]
    if last == " " || last == "@" || last == '*'
      f = f.chop
    end
  end
  nextpos = nil

  # could be a bookmark with position attached to it
  if f.index(":")
    f, nextpos = f.split(":")
  end
  if File.directory? f
    save_dir_pos
    change_dir f, nextpos
  elsif File.readable? f
    $default_command ||= "$EDITOR"
    if !$editor_mode
      ft = filetype f
      if ft
        comm = $pager_command[ft]
      else
        comm = $pager_command[File.extname(f)]
        comm = $pager_command["unknown"] unless comm
      end
    else
      comm = $default_command
    end
    comm ||= $default_command
    if comm.index("%%")
      comm = comm.gsub("%%", Shellwords.escape(f))
    else
      comm = comm + " #{Shellwords.escape(f)}"
    end
    system("#{comm}")
    f = Dir.pwd + "/" + f if f[0] != '/'
    $visited_files.insert(0, f)
    push_used_dirs Dir.pwd
  else
    perror "open_file: (#{f}) not found"
      # could check home dir or CDPATH env variable DO
  end
end

## run command on given file/s
#   Accepts command from user
#   After putting readline in place of gets, pressing a C-c has a delayed effect. It goes intot
#   exception bloack after executing other commands and still does not do the return !
def TODOrun_command f
  files=nil
  case f
  when Array
    # escape the contents and create a string
    files = Shellwords.join(f)
  when String
    files = Shellwords.escape(f)
  end
  print "Run a command on #{files}: "
  begin
    #Readline::HISTORY.push(*values) 
    command = Readline::readline('>', true)
    #command = gets().chomp
    return if command.size == 0
    print "Second part of command: "
    #command2 = gets().chomp
    command2 = Readline::readline('>', true)
    puts "#{command} #{files} #{command2}"
    system "#{command} #{files} #{command2}"
  rescue Exception => ex
    perror "Canceled command, (#{ex}) press a key"
    return
  end
  begin
  rescue Exception => ex
  end

  c_refresh
  puts "Press a key ..."
  push_used_dirs Dir.pwd
  get_char
end

## clear sort order and refresh listing, used typically if you are in some view
#  such as visited dirs or files
def escape
  $sorto = nil
  $sorto = $default_sort_order
  $viewctr = 0
  $title = nil
  $filterstr = "M"
  visual_block_clear
  c_refresh
end

## refresh listing after some change like option change, or toggle
# I think NCurses has a refresh which when called internally results in this chap
# getting called since both are included. or maybe App or somehting has a refresh
def c_refresh
  $filterstr ||= "M"
  #$files = `zsh -c 'print -rl -- *(#{$sorto}#{$hidden}#{$filterstr})'`.split("\n")
  $patt=nil
  $title = nil
  display_dir
end
#
## unselect all files
def unselect_all
  $selected_files = []
  $visual_mode = nil
end

## select all files
def select_all
  $selected_files = $view.dup
end

## accept dir to goto and change to that ( can be a file too)
def goto_dir
  begin
    path = get_string "Enter path: "
    return if path.nil? || path == ""
  rescue Exception => ex
    perror "Cancelled cd, press a key"
    return
  end
  f = File.expand_path(path)
  unless File.directory? f
    ## check for env variable
    tmp = ENV[path]
    if tmp.nil? || !File.directory?( tmp )
      ## check for dir in home 
      tmp = File.expand_path("~/#{path}")
      if File.directory? tmp
        f = tmp
      end
    else
      f = tmp
    end
  end

  open_file f
end

## toggle mode to selection or not
#  In selection, pressed hotkey selects a file without opening, one can keep selecting
#  (or deselecting).
#
def selection_mode_toggle
  if $mode == 'SEL'
    # we seem to be coming out of select mode with some files
    if $selected_files.size > 0
      run_command $selected_files
    end
    $mode = nil
  else
    #$selection_mode = !$selection_mode
    $mode = 'SEL'
  end
end
## toggle command mode
def command_mode
  if $mode == 'COM'
    $mode = nil
    return
  end
  $mode = 'COM'
end
def goto_parent_dir
  change_dir ".."
end
## This actually filters, in zfm it goes to that entry since we have a cursor there
#
def goto_entry_starting_with fc=nil
  unless fc
    print "Entries starting with: "
    fc = get_char
  end
  return if fc.size != 1
  ## this is wrong and duplicates the functionality of /
  #  It shoud go to cursor of item starting with fc
  $patt = "^#{fc}"
end
def OLDgoto_bookmark ch=nil
  unless ch
    print "Enter bookmark char: "
    ch = get_char
  end
  if ch =~ /^[0-9A-Z]$/
    d = $bookmarks[ch]
    # this is if we use zfm's bookmarks which have a position
    # this way we leave the position as is, so it gets written back
    nextpos = nil
    if d
      if d.index(":")
        ix = d.index(":")
        nextpos = d[ix+1..-1]
        d = d[0,ix]
      end
      change_dir d, nextpos
    else
      perror "#{ch} not a bookmark"
    end
  else
    #goto_entry_starting_with ch
    file_starting_with ch
  end
end


## take regex from user, to run on files on screen, user can filter file names
def enter_regex
  patt = get_string "Enter (regex) pattern: "
  #$patt = gets().chomp
  #$patt = Readline::readline('>', true)
  $patt = patt
  return patt
end
def next_page
  $sta += $pagesize
end
def prev_page
  $sta -= $pagesize
end
def TODOshow_marks
  puts
  puts "Bookmarks: "
  $bookmarks.each_pair { |k, v| puts "#{k.ljust(7)}  =>  #{v}" }
  puts
  print "Enter bookmark to goto: "
  ch = get_char
  goto_bookmark(ch) if ch =~ /^[0-9A-Z]$/
end
# MENU MAIN -- keep consistent with zfm
def main_menu
  h = { 
    :a => :ack,
    "/" => :ffind,
    :l => :locate,
    :v => :viminfo,
    :z => :z_interface,
    :d => :child_dirs,
    :r => :recent_files,
    :t => :dirtree,
    "4" => :tree,
    :s => :sort_menu, 
    :F => :filter_menu,
    :c => :command_menu ,
    :B => :bindkey_ext_command,
    :M => :newdir,
    "%" => :newfile,
    :x => :extras
  }
  menu "Main Menu", h
end
def TODOmenu title, h
  return unless h

  pbold "#{title}"
  h.each_pair { |k, v| puts " #{k}: #{v}" }
  ch = get_char
  binding = h[ch]
  binding = h[ch.to_sym] unless binding
  if binding
    if respond_to?(binding, true)
      send(binding)
    end
  end
  return ch, binding
end
def toggle_menu
  h = { :h => :toggle_hidden, :c => :toggle_case, :l => :toggle_long_list , "1" => :toggle_columns, 
  :p => :toggle_pager_mode, :e => :toggle_enhanced_list}
  ch, menu_text = menu "Toggle Menu", h
  case menu_text
  when :toggle_hidden
    $hidden = $hidden ? nil : "D"
    c_refresh
  when :toggle_case
    #$ignorecase = $ignorecase ? "" : "i"
    $ignorecase = !$ignorecase
    c_refresh
  when :toggle_columns
    $gviscols = 3 if $gviscols == 1
    #$long_listing = false if $gviscols > 1 
    x = $grows * $gviscols
    $pagesize = $pagesize==x ? $grows : x
  when :toggle_pager_mode
    $editor_mode = !$editor_mode
    if $editor_mode
      $default_command = nil
    else
      $default_command = ENV['MANPAGER'] || ENV['PAGER']
    end
  when :toggle_enhanced_list
    $enhanced_mode = !$enhanced_mode

  when :toggle_long_list
    $long_listing = !$long_listing
    if $long_listing
      $gviscols = 1
      $pagesize = $grows
    else
      x = $grows * $gviscols
      $pagesize = $pagesize==x ? $grows : x
    end
    c_refresh
  end
end

def sort_menu
  lo = nil
  h = { :n => :newest, :a => :accessed, :o => :oldest, 
    :l => :largest, :s => :smallest , :m => :name , :r => :rname, :d => :dirs, :c => :clear }
  ch, menu_text = menu "Sort Menu", h
  case menu_text
  when :newest
    lo="om"
  when :accessed
    lo="oa"
  when :oldest
    lo="Om"
  when :largest
    lo="OL"
  when :smallest
    lo="oL"
  when :name
    lo="on"
  when :rname
    lo="On"
  when :dirs
    lo="/"
  when :clear
    lo=""
  end
  ## This needs to persist and be a part of all listings, put in change_dir.
  $sorto = lo
  $files = `zsh -c 'print -rl -- *(#{lo}#{$hidden}M)'`.split("\n") if lo
  $title = nil
  #$files =$(eval "print -rl -- ${pattern}(${MFM_LISTORDER}$filterstr)")
end

def command_menu
  ## 
  #  since these involve full paths, we need more space, like only one column
  #
  ## in these cases, getting back to the earlier dir, back to earlier listing
  # since we've basically overlaid the old listing
  #
  # should be able to sort THIS listing and not rerun command. But for that I'd need to use
  # xargs ls -t etc rather than the zsh sort order. But we can run a filter using |.
  #
  h = { :t => :today, :D => :default_command , :R => :remove_from_list}
  if $editor_mode 
    h[:e] = :pager_mode
  else
    h[:e] = :editor_mode
  end
  ch, menu_text = menu "Command Menu", h
  case menu_text
  when :pager_mode
    $editor_mode = false
    $default_command = ENV['MANPAGER'] || ENV['PAGER']
  when :editor_mode
    $editor_mode = true
    $default_command = nil
  when :ffind
    ffind
  when :locate
    locate
  when :today
    $files = `zsh -c 'print -rl -- *(#{$hidden}Mm0)'`.split("\n")
    $title = "Today's files"
  when :default_command
    print "Selecting a file usually invokes $EDITOR, what command do you want to use repeatedly on selected files: "
    $default_command = gets().chomp
    if $default_command != ""
      print "Second part of command (maybe blank): "
      $default_command2 = gets().chomp
    else
      print "Cleared default command, will default to $EDITOR"
      $default_command2 = nil
      $default_command = nil
    end
  end
end
def extras
  h = { "1" => :one_column, "2" => :multi_column, :c => :columns, :r => :config_read , :w => :config_write}
  ch, menu_text = menu "Extras Menu", h
  case menu_text
  when :one_column
    $pagesize = $grows
  when :multi_column
    #$pagesize = 60
    $pagesize = $grows * $gviscols
  when :columns
    print "How many columns to show: 1-6 [current #{$gviscols}]? "
    ch = get_char
    ch = ch.to_i
    if ch > 0 && ch < 7
      $gviscols = ch.to_i
      $pagesize = $grows * $gviscols
    end
  end
end
def filter_menu
  h = { :d => :dirs, :f => :files, :e => :emptydirs , "0" => :emptyfiles}
  ch, menu_text = menu "Filter Menu", h
  files = nil
  case menu_text
  when :dirs
    $filterstr = "/M"
    files = `zsh -c 'print -rl -- *(#{$sorto}/M)'`.split("\n")
    $title = "Filter: directories only"
  when :files
    $filterstr = "."
    files = `zsh -c 'print -rl -- *(#{$sorto}#{$hidden}.)'`.split("\n")
    $title = "Filter: files only"
  when :emptydirs
    $filterstr = "/D^F"
    files = `zsh -c 'print -rl -- *(#{$sorto}/D^F)'`.split("\n")
    $title = "Filter: empty directories"
  when :emptyfiles
    $filterstr = ".L0"
    files = `zsh -c 'print -rl -- *(#{$sorto}#{$hidden}.L0)'`.split("\n")
    $title = "Filter: empty files"
  end
  if files
    $files = files
    show_list
    $stact = 0
  end
end
def select_used_dirs
  $title = "Used Directories"
  $files = $used_dirs.uniq
  #show_list
end
def select_visited_files
  # not yet a unique list, needs to be unique and have latest pushed to top
  $title = "Visited Files"
  files = $visited_files.uniq
  show_list files
  $title = nil
end
def select_bookmarks
  $title = "Bookmarks"
  $files = $bookmarks.values.collect do |x| 
    if x.include? ":"
      ix = x.index ":"
      x[0,ix]
    else
      x
    end
  end
  #show_list files
end

## part copied and changed from change_dir since we don't dir going back on top
#  or we'll be stuck in a cycle
def pop_dir
  # the first time we pop, we need to put the current on stack
  if !$visited_dirs.index(Dir.pwd)
    $visited_dirs.push Dir.pwd
  end
  ## XXX make sure thre is something to pop
  d = $visited_dirs.delete_at 0
  ## XXX make sure the dir exists, cuold have been deleted. can be an error or crash otherwise
  $visited_dirs.push d
  Dir.chdir d
  display_dir

  return
  # old stuff with zsh
  $filterstr ||= "M"
  $files = `zsh -c 'print -rl -- *(#{$sorto}#{$hidden}#{$filterstr})'`.split("\n")
  post_cd
end
# TODO
def TODOpost_cd
  $patt=nil
  $sta = $cursor = 0
  $title = nil
  if $selected_files.size > 0
    $selected_files = []
  end
  $visual_block_start = nil
  $stact = 0
  screen_settings
  # i think this will screw with the dir_pos since it is not filename based.
  enhance_file_list
  revert_dir_pos
end
#
## read dirs and files and bookmarks from file
def config_read
  #f =  File.expand_path("~/.zfminfo")
  f =  File.expand_path(CONFIG_FILE)
  if File.readable? f
    load f
    # maybe we should check for these existing else crash will happen.
    $used_dirs.push(*(DIRS.split ":"))
    $used_dirs.concat get_env_paths
    $visited_files.push(*(FILES.split ":"))
    #$bookmarks.push(*bookmarks) if bookmarks
    chars = ('A'..'Z').to_a
    chars.concat( ('0'..'9').to_a )
    chars.each do |ch|
      if Kernel.const_defined? "BM_#{ch}"
        $bookmarks[ch] = Kernel.const_get "BM_#{ch}"
      end
    end
  end
end
def get_env_paths
  files = []
  %w{ GEM_HOME PYTHONHOME}.each do |p|
    d = ENV[p]
    files.push d if d
  end
  %w{ RUBYLIB RUBYPATH GEM_PATH PYTHONPATH }.each do |p|
    d = ENV[p]
    files.concat d.split(":") if d
  end
  return files
end

## save dirs and files and bookmarks to a file
def config_write
  # Putting it in a format that zfm can also read and write
  #f1 =  File.expand_path("~/.zfminfo")
  f1 =  File.expand_path(CONFIG_FILE)
  d = $used_dirs.join ":"
  f = $visited_files.join ":"
  File.open(f1, 'w+') do |f2|  
    # use "\n" for two lines of text  
    f2.puts "DIRS=\"#{d}\""
    f2.puts "FILES=\"#{f}\""
    $bookmarks.each_pair { |k, val| 
      f2.puts "BM_#{k}=\"#{val}\""
      #f2.puts "BOOKMARKS[\"#{k}\"]=\"#{val}\""
    }
  end
  $writing = $modified = false
end

## accept a character to save this dir as a bookmark
def create_bookmark
  print "Enter A to Z or 0-9 for bookmark: "
  ch = get_char
  if ch =~ /^[0-9A-Z]$/
    $bookmarks[ch] = "#{Dir.pwd}:#{$cursor}"
    $modified = true
  else
    perror "Bookmark must be upper-case character or number."
  end
end
def subcommand
  print "Enter command: "
  begin
    #command = gets().chomp
    command = Readline::readline('>', true)
    return if command == ""
  rescue Exception => ex
    return
  end
  if command == "q"
    if $modified
      print "Do you want to save bookmarks? (y/n): "
      ch = get_char
      if ch == "y"
        $writing = true
        $quitting = true
      elsif ch == "n"
        $quitting = true
        print "Quitting without saving bookmarks"
      else
        perror "No action taken."
      end
    else
      $quitting = true
    end
  elsif command == "wq"
    $quitting = true
    $writing = true
  elsif command == "x"
    $quitting = true
    $writing = true if $modified
  elsif command == "p"
    system "echo $PWD | pbcopy"
    puts "Stored PWD in clipboard (using pbcopy)"
  end
end
def quit_command
  if $modified
    puts "Press w to save bookmarks before quitting " if $modified
    print "Press another q to quit "
    ch = get_char
  else
    $quitting = true
  end
  $quitting = true if ch == "q"
  $quitting = $writing = true if ch == "w"
end

def views
  views=%w[/ om oa Om OL oL On on]
  viewlabels=%w[Dirs Newest Accessed Oldest Largest Smallest Reverse Name]
  $sorto = views[$viewctr]
  $title = viewlabels[$viewctr]
  $viewctr += 1
  $viewctr = 0 if $viewctr > views.size

  $files = `zsh -c 'print -rl -- *(#{$sorto}#{$hidden}M)'`.split("\n")

end
def child_dirs
  $title = "Child directories"
  $files = `zsh -c 'print -rl -- *(/#{$sorto}#{$hidden}M)'`.split("\n")
end
def dirtree
  $title = "Child directories"
  $files = `zsh -c 'print -rl -- **/*(/#{$sorto}#{$hidden}M)'`.split("\n")
end
#
# Get a full recursive listing of what's in this dir - useful for small projects with more
# structure than files.
def tree
  # Caution: use only for small projects, don't use in root.
  $title = "Full Tree"
  $files = `zsh -c 'print -rl -- **/*(#{$sorto}#{$hidden}M)'`.split("\n")
end
def recent_files
  # print -rl -- **/*(Dom[1,10])
  $title = "Recent files"
  $files = `zsh -c 'print -rl -- **/*(Dom[1,15])'`.split("\n")
end
def select_current
  ## vp is local there, so i can do $vp[0]
  #open_file $view[$sta] if $view[$sta]
  open_file $view[$cursor] if $view[$cursor]
end

## create a list of dirs in which some action has happened, for saving
def push_used_dirs d=Dir.pwd
  $used_dirs.index(d) || $used_dirs.push(d)
end
## I thin we need to make this like the command line one TODO
def get_char
  c = @window.getchar
  case c
  when 13,10
    return "ENTER"
  when 32
    return "SPACE"
  when 127
    return "BACKSPACE"
  when 27
    return "ESCAPE"
  end
  keycode_tos c
#  if c > 32 && c < 127
    #return c.chr
  #end
  ## use keycode_tos from Utils.
end

def pbold text
  #puts "#{BOLD}#{text}#{BOLD_OFF}"
  alert text
end
def perror text
  ##puts "#{RED}#{text}#{CLEAR}"
  #get_char
  alert text
end
def pause text=" Press a key ..."
  #print text
  #get_char
end
## return shortcut for an index (offset in file array)
# use 2 more arrays to make this faster
#  if z or Z take another key if there are those many in view
#  Also, display ROWS * COLS so now we are not limited to 60.
def get_shortcut ix
  return "<" if ix < $stact
  ix -= $stact
  i = $IDX[ix]
  return i if i
  return "->"
end
## returns the integer offset in view (file array based on a-y za-zz and Za - Zz
# Called when user types a key
#  should we even ask for a second key if there are not enough rows
#  What if we want to also trap z with numbers for other purposes
def get_index key, vsz=999
  i = $IDX.index(key)
  return i+$stact if i
  #sz = $IDX.size
  zch = nil
  if vsz > 25
    if key == "z" || key == "Z"
      print key
      zch = get_char
      print zch
      i = $IDX.index("#{key}#{zch}")
      return i+$stact if i
    end
  end
  return nil
end

def delete_file
  file_actions :delete
end

## generic external command program
#  prompt is the user friendly text of command such as list for ls, or extract for dtrx, page for less
#  pauseyn is whether to pause after command as in file or ls
#
def command_file prompt, *command
  pauseyn = command.shift
  command = command.join " "
    print "[#{prompt}] Choose a file [#{$view[$cursor]}]: "
    file = ask_hint $view[$cursor]
  #print "#{prompt} :: Enter file shortcut: "
  #file = ask_hint
  perror "Command Cancelled" unless file
  return unless file
  file = File.expand_path(file)
  if File.exists? file
    file = Shellwords.escape(file)
    pbold "#{command} #{file} (#{pauseyn})"
    system "#{command} #{file}"
    pause if pauseyn == "y"
    c_refresh
  else
    perror "File #{file} not found"
  end
end

## prompt user for file shortcut and return file or nil
#
def ask_hint deflt=nil
  f = nil
  ch = get_char
  if ch == "ENTER" 
    return deflt
  end
  ix = get_index(ch, $viewport.size)
  f = $viewport[ix] if ix
  return f
end

## check screen size and accordingly adjust some variables
#
def screen_settings
  # TODO these need to become part of our new full_indexer class, not hang about separately.
  $glines=%x(tput lines).to_i
  $gcols=%x(tput cols).to_i
  # this depends now on textpad size not screen size TODO FIXME
  $grows = $glines - 1
  $pagesize = 60
  #$gviscols = 3
  $pagesize = $grows * $gviscols
end
## moves column offset so we can reach unindexed columns or entries
# 0 forward and any other back/prev
def column_next dir=0
  if dir == 0
    $stact += $grows
    $stact = 0 if $stact >= $viewport.size
  else
    $stact -= $grows
    $stact = 0 if $stact < 0
  end
end
# currently i am only passing the action in from the list there as a key
# I should be able to pass in new actions that are external commands
def file_actions action=nil
  h = { :d => :delete, :m => :move, :r => :rename, :v => ENV["EDITOR"] || :vim,
    :c => :copy, :C => :chdir,
    :l => :less, :s => :most , :f => :file , :o => :open, :x => :dtrx, :z => :zip }
  #acttext = h[action.to_sym] || action
  acttext = action || ""
  file = nil

  sct = $selected_files.size
  if sct > 0
    text = "#{sct} files"
    file = $selected_files
  else
    print "[#{acttext}] Choose a file [#{$view[$cursor]}]: "
    file = ask_hint $view[$cursor]
    return unless file
    text = file
  end

  case file
  when Array
    # escape the contents and create a string
    files = Shellwords.join(file)
  when String
    files = Shellwords.escape(file)
  end


  ch = nil
  if action
      menu_text = action
  else
    ch, menu_text = menu "File Menu for #{text}", h
    menu_text = :quit if ch == "q"
  end
  case menu_text.to_sym
  when :quit
  when :delete
    print "rmtrash #{files} ?[yn]: "
    ch = get_char
    return if ch != "y"
    system "rmtrash #{files}"
    c_refresh
  when :move
    print "move #{text} to : "
    #target = gets().chomp
    target = Readline::readline('>', true)
    text=File.expand_path(text)
    return if target == ""
    if File.directory? target
      FileUtils.mv text, target
      c_refresh
    else
      perror "Target not a dir"
    end
  when :copy
    print "copy #{text} to : "
    target = Readline::readline('>', true)
    return if target == ""
    text=File.expand_path(text)
    target = File.basename(text) if target == "."
    if File.exists? target
      perror "Target (#{target}) exists"
    else
      FileUtils.cp text, target
      c_refresh
    end
  when :chdir
    change_dir File.dirname(text)
  when :zip
    print "Archive name: "
    #target = gets().chomp
    target = Readline::readline('>', true)
    return if target == ""
    # don't want a blank space or something screwing up
    if target && target.size > 3
      if File.exists? target
        perror "Target (#{target}) exists"
      else
        system "tar zcvf #{target} #{files}"
        c_refresh
      end
    end
  when :rename
  when :most, :less, :vim
    system "#{menu_text} #{files}"
  else
    return unless menu_text
    print "#{menu_text} #{files}"
    pause
    print
    system "#{menu_text} #{files}"
    c_refresh
    pause
  end
  # remove non-existent files from select list due to move or delete or rename or whatever
  if sct > 0
    $selected_files.reject! {|x| x = File.expand_path(x); !File.exists?(x) }
  end
end

def columns_incdec howmany
  $gviscols += howmany.to_i
  $gviscols = 1 if $gviscols < 1
  $gviscols = 6 if $gviscols > 6
  $pagesize = $grows * $gviscols
end

# bind a key to an external command wich can be then be used for files
def bindkey_ext_command
  print 
  pbold "Bind a capital letter to an external command"
  print "Enter a capital letter to bind: "
  ch = get_char
  return if ch == "Q"
  if ch =~ /^[A-Z]$/
    print "Enter an external command to bind to #{ch}: "
    com = gets().chomp
    if com != ""
      print "Enter prompt for command (blank if same as command): "
      pro = gets().chomp
      pro = com if pro == ""
    end
    print "Pause after output [y/n]: "
    yn = get_char
    $bindings[ch] = "command_file #{pro} #{yn} #{com}"
  end
end
def viminfo
  file = File.expand_path("~/.viminfo")
  if File.exists? file
    $title = "Files from ~/.viminfo"
    #$files = `grep '^>' ~/.viminfo | cut -d ' ' -f 2- | sed "s#~#$HOME#g"`.split("\n")
    $files = `grep '^>' ~/.viminfo | cut -d ' ' -f 2- `.split("\n")
    $files.reject! {|x| x = File.expand_path(x); !File.exists?(x) }
    show_list
  end
end
def z_interface
  file = File.expand_path("~/.z")
  if File.exists? file
    $title = "Directories from ~/.z"
    $files = `sort -rn -k2 -t '|' ~/.z | cut -f1 -d '|'`.split("\n")
    home = ENV['HOME']
    $files.collect! do |f| 
      f.sub(/#{home}/,"~")
    end
    show_list
  end
end
def ack
  pattern = get_string "Enter a pattern to search (ack): "
  return if pattern.nil? || pattern == ""
  $title = "Files found using 'ack' #{pattern}"
  #system("ack #{pattern}")
  #pause
  files = `ack -l #{pattern}`.split("\n")
  if files.size == 0
    perror "No files found."
  else
    $files = files
    show_list
  end
end
def ffind
  pattern = get_string "Enter a file name pattern to find: "
  return if pattern.nil? || pattern == ""
  $title = "Files found using 'find' #{pattern}"
  files = `find . -name '#{pattern}'`.split("\n")
  if files.size == 0
    perror "No files found."
  else
    $files = files
    show_list
  end
end
def locate
  pattern = get_string "Enter a file name pattern to locate: "
  return if pattern.nil? || pattern == ""
  $title = "Files found using 'locate' #{pattern}"
  files = `locate #{pattern}`.split("\n")
  files.reject! {|x| x = File.expand_path(x); !File.exists?(x) }
  if files.size == 0
    perror "No files found."
  else
    $files = files
    show_list
  end
end

## Displays files from .viminfo file, if you use some other editor which tracks files opened
#  then you can modify this accordingly.
#

##  takes directories from the z program, if you use autojump you can
#   modify this accordingly
#

## some cursor movement functions
##
#
def cursor_scroll_dn
  moveto(pos() + MSCROLL)
end
def cursor_scroll_up
  moveto(pos() - MSCROLL)
end
def cursor_dn
  moveto(pos() + 1)
end
def cursor_up
  moveto(pos() - 1)
end
def pos
  $cursor
end

def moveto pos
  orig = $cursor
  $cursor = pos
  $cursor = [$cursor, $view.size - 1].min
  $cursor = [$cursor, 0].max
  star = [orig, $cursor].min
  fin = [orig, $cursor].max
  if $visual_mode
    # PWD has to be there in selction
    if $selected_files.index $view[$cursor]
      # this depends on the direction 
      $selected_files = $selected_files - $view[star..fin]
      ## current row remains in selection always.
      $selected_files.push $view[$cursor]
    else
      $selected_files.concat $view[star..fin]
    end
  end
end
def visual_mode_toggle
  $visual_mode = !$visual_mode
  if $visual_mode
    $visual_block_start = $cursor
    $selected_files.push $view[$cursor]
  end
end
def visual_block_clear
  if $visual_block_start
    star = [$visual_block_start, $cursor].min
    fin = [$visual_block_start, $cursor].max
    $selected_files = $selected_files - $view[star..fin]
  end
  $visual_block_start = nil
  $visual_mode = nil
end
def file_matching? file, patt
  file =~ /#{patt}/
end

## generic method to take cursor to next position for a given condition
def return_next_match binding, *args
  first = nil
  ix = 0
  $view.each_with_index do |elem,ii|
    if binding.call(elem, *args)
      first ||= ii
      if ii > $cursor 
        ix = ii
        break
      end
    end
  end
  return first if ix == 0
  return ix
end
##
# position cursor on a specific line which could be on a nother page
# therefore calculate the correct start offset of the display also.
def goto_line pos
  pages = ((pos * 1.00)/$pagesize).ceil
  pages -= 1
  #$sta = pages * $pagesize + 1
  $sta = pages * $pagesize + 0
  $cursor = pos
  #$log.debug "XXX: GOTO_LINE #{$sta} :: #{$cursor}"
end
def filetype f
  return nil unless f
  f = Shellwords.escape(f)
  s = `file #{f}`
  if s.index "text"
    return :text
  elsif s.index(/[Zz]ip/)
    return :zip
  elsif s.index("archive")
    return :zip
  elsif s.index "image"
    return :image
  elsif s.index "data"
    return :text
  end
  nil
end

def save_dir_pos 
  return if $sta == 0 && $cursor == 0
  $dir_position[Dir.pwd] = [$sta, $cursor]
end
def revert_dir_pos
  $sta = 0
  $cursor = 0
  a = $dir_position[Dir.pwd]
  if a
    $sta = a.first
    $cursor = a[1]
    raise "sta is nil for #{Dir.pwd} : #{$dir_position[Dir.pwd]}" unless $sta
    raise "cursor is nil" unless $cursor
  end
end
def newdir
  print 
  print "Enter directory name: "
  str = Readline::readline('>', true)
  return if str == ""
  if File.exists? str
    perror "#{str} exists."
    return
  end
  begin
    FileUtils.mkdir str
    $used_dirs.insert(0, str) if File.exists?(str)
    c_refresh
  rescue Exception => ex
    perror "Error in newdir: #{ex}"
  end
end
def newfile
  print 
  print "Enter file name: "
  str = Readline::readline('>', true)
  return if str == ""
  system "$EDITOR #{str}"
  $visited_files.insert(0, str) if File.exists?(str)
  c_refresh
end

##
# Editing of the User Dir List. 
# remove current entry from used dirs list, since we may not want some entries being there
#
def remove_from_list
  if $selected_files.size > 0
    sz = $selected_files.size
    print "Remove #{sz} files from used list (y)?: "
    ch = get_char
    return if ch != "y"
    $used_dirs = $used_dirs - $selected_files
    $visited_files = $visited_files - $selected_files
    unselect_all
    $modified = true
    return
  end
  print
  ## what if selected some rows
  file = $view[$cursor]
  print "Remove #{file} from used list (y)?: "
  ch = get_char
  return if ch != "y"
  file = File.expand_path(file)
  if File.directory? file
    $used_dirs.delete(file)
  else
    $visited_files.delete(file)
  end
  c_refresh
  $modified = true
end
#
# If there's a short file list, take recently mod and accessed folders and put latest
# files from there and insert it here. I take both since recent mod can be binaries / object
# files and gems created by a process, and not actually edited files. Recent accessed gives
# latest source, but in some cases even this can be misleading since running a program accesses
# include files.
def enhance_file_list
  return unless $enhanced_mode
  # if only one entry and its a dir
  # get its children and maybe the recent mod files a few
  
  if $files.size == 1
    # its a dir, let give the next level at least
    if $files.first[-1] == "/"
      d = $files.first
      f = `zsh -c 'print -rl -- #{d}*(omM)'`.split("\n")
      if f && f.size > 0
        $files.concat f
        return
      end
    else
      # just a file, not dirs here
      return
    end
  end
  # 
  # check if a ruby project dir, although it could be a backup file too,
  # if so , expand lib and maby bin, put a couple recent files
  #
  if $files.index("Gemfile") || $files.grep(/\.gemspec/).size > 0
    # usually the lib dir has only one file and one dir
    flg = false
    if $files.index("lib/")
      f = `zsh -c 'print -rl -- lib/*(om[1,5]M)'`.split("\n")
      if f && f.size() > 0
        insert_into_list("lib/", f)
        flg = true
      end
      dd = File.basename(Dir.pwd)
      if f.index("lib/#{dd}/")
        f = `zsh -c 'print -rl -- lib/#{dd}/*(om[1,5]M)'`.split("\n")
        if f && f.size() > 0
          insert_into_list("lib/#{dd}/", f)
          flg = true
        end
      end
    end
    if $files.index("bin/")
      f = `zsh -c 'print -rl -- bin/*(om[1,5]M)'`.split("\n")
      insert_into_list("bin/", f) if f && f.size() > 0
      flg = true
    end
    return if flg

    # lib has a dir in it with the gem name

  end
  return if $files.size > 15

  ## first check accessed else modified will change accessed
  moda = `zsh -c 'print -rn -- *(/oa[1]M)'`
  if moda && moda != ""
    modf = `zsh -c 'print -rn -- #{moda}*(oa[1]M)'`
    if modf && modf != ""
      insert_into_list moda, modf
    end
    modm = `zsh -c 'print -rn -- #{moda}*(om[1]M)'`
    if modm && modm != "" && modm != modf
      insert_into_list moda, modm
    end
  end
  ## get last modified dir
  modm = `zsh -c 'print -rn -- *(/om[1]M)'`
  if modm != moda
    modmf = `zsh -c 'print -rn -- #{modm}*(oa[1]M)'`
    insert_into_list modm, modmf
    modmf1 = `zsh -c 'print -rn -- #{modm}*(om[1]M)'`
    insert_into_list(modm, modmf1) if modmf1 != modmf
  else
    # if both are same then our options get reduced so we need to get something more
    # If you access the latest mod dir, then come back you get only one, since mod and accessed
    # are the same dir, so we need to find the second modified dir
  end
end
def insert_into_list dir, file
  ix = $files.index(dir)
  raise "something wrong can find #{dir}." unless ix
  $files.insert ix, *file
end

#run if __FILE__ == $PROGRAM_NAME
end
