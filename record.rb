#!/usr/bin/env ruby
# encoding: utf-8

require 'Qt4'
require 'qtuitools'

class WordModel < Qt::AbstractTableModel
  def initialize(parent = nil)
    super parent
    @words = open("words.txt").read.split("\n")
    @blacklist = open("words-blacklist.txt").read.split("\n")
    @words.reject!{ |w| @blacklist.include? w }
    @diacritics = @words.map{|w| diacritic(w)}
    
    # Init word directories
    %w[wav wav/unmarked wav/acute wav/grave wav/hook wav/tilde wav/dot].each do |dir|
      if !Dir.exists? dir
        Dir.mkdir dir
      end
    end
  end
  
  def rowCount(parent)
    @words.count
  end
  
  def columnCount(parent)
    4
  end
  
  def data(index, role = Qt::DisplayRole)
    case role 
    when Qt::DisplayRole
      case index.column
      when 0
        Qt::Variant.new(exists?(index) ? tr("Recorded") : tr("N/A"))
      when 1
        Qt::Variant.new @diacritics[index.row].capitalize
      when 2
        Qt::Variant.new @words[index.row]
      when 3
        Qt::Variant.new "wav/#{@diacritics[index.row]}/#{@words[index.row]}.wav"
      else
        Qt::Variant.new
      end
    else
      Qt::Variant.new
    end
  end
  
  def original_data(index)
    @words[index.row]
  end
  
  def headerData(section, orientation, role = Qt::DisplayRole)
    if role == Qt::DisplayRole
      if orientation == Qt::Horizontal
        Qt::Variant.new [tr("Availlability"), tr("Diacritic"), tr("Word"), tr("Path")][section]
      else
        super
      end
    else
      Qt::Variant.new
    end
  end
  
  def exists?(index)
    File.exists? "wav/#{diacritic(original_data(index))}/#{original_data(index)}.wav"
  end
  
  def diacritic(word)
    case word
    when /[áắấéếíóốớúứý]/
      "acute"
    when /[àằầèềìòồờùừỳ]/
      "grave"
    when /[ảẳẩẻểỉỏổởủửỷ]/
      "hook"
    when /[ãẵẫẽễĩõỗỡũữỹ]/
      "tilde"
    when /[ạặậẹệịọộợụựỵ]/
      "dot"
    else
      "unmarked"
    end
  end
end

class WordFilterModel < Qt::SortFilterProxyModel
  def initialize
    super
  end
  
  def filter
    @filter ||= {
      record_availability: 'all',
      diacritics: ['unmarked', 'acute', 'grave', 'hook', 'tilde', 'dot']
    }
  end
  
  def setFilter(filter)
    @filter = filter
    reset
  end
  
  def filterAcceptsRow(source_row, source_parent_index)
    availability_idx    = sourceModel.index(source_row, 0, source_parent_index)
    diacritic_idx       = sourceModel.index(source_row, 1, source_parent_index)
    
    # Filter by availability
    if filter[:record_availability] == 'all'
      availability_valid = true
    else
#       availability_regexp = Regexp.new("#{filter[:record_availability]}", Regexp::IGNORECASE)
#       availability_valid = !sourceModel.data(availability_idx).toString.match(availability_regexp).nil?
      if filter[:record_availability] == 'recorded'
        availability_valid = sourceModel.data(availability_idx).toString == tr("Recorded")
      else
        availability_valid = sourceModel.data(availability_idx).toString == tr("N/A")
      end
    end
    
    # Filter by diacritic
#     diacritic_regexp = Regexp.new("^(#{filter[:diacritics].join("|")})$", Regexp::IGNORECASE)
#     diacritic_valid = !sourceModel.data(diacritic_idx).toString.match(diacritic_regexp).nil?
    diacritic_valid = (filter[:diacritics].map(&:capitalize).include?(sourceModel.data(diacritic_idx).toString))
    
    return availability_valid && diacritic_valid
  end
  
  def headerData(section, orientation, role = Qt::DisplayRole)
    if role == Qt::DisplayRole && orientation == Qt::Vertical
      Qt::Variant.new section + 1
    else
      super
    end
  end
end

class RecordApp < Qt::Application
  TIMER_INTERVAL = 1
  MAX_RECORD_TIME = 600
  
  def initialize(argv)
    super argv
    
    file = Qt::File.new 'record.ui' do
      open Qt::File::ReadOnly
    end
    
    window = Qt::UiLoader.new.load file
    
    file.close
    
    if window.nil?
      print "Error. Window is nil.\n"
      exit
    end
    
    # Extract children
    @play_button            = window.findChild Qt::PushButton, "playButton"
    @record_button          = window.findChild Qt::PushButton, "recordButton"
    @reload_button          = window.findChild Qt::PushButton, "reloadButton"
    @record_progress_bar    = window.findChild Qt::ProgressBar, "recordProgressBar"
    @word_table_view        = window.findChild Qt::TableView, "wordTableView"
    @action_play            = window.findChild Qt::Action, "actionPlay"
    @action_record          = window.findChild Qt::Action, "actionRecord"
    
    # Set record time to progress bar
    @record_progress_bar.setMaximum MAX_RECORD_TIME
    
    # Connect children signals
    connect(@play_button, SIGNAL('clicked()'), SLOT('onPlayBtnClicked()'))
    connect(@record_button, SIGNAL('clicked()'), SLOT('onRecordBtnClicked()'))
    connect(@reload_button, SIGNAL('clicked()'), SLOT('onReloadBtnClicked()'))
    connect(@action_play, SIGNAL('triggered()'), SLOT('onPlayBtnClicked()'))
    connect(@action_record, SIGNAL('triggered()'), SLOT('onRecordBtnClicked()'))
    connect(@word_table_view, SIGNAL('clicked(QModelIndex)'), SLOT('onWordListClicked(QModelIndex)'))
    connect(@word_table_view, SIGNAL('doubleClicked(QModelIndex)'), SLOT('onWordListDoubleClicked(QModelIndex)'))
    
    # Assign model
    @word_model        = WordModel.new
    @proxy_model = WordFilterModel.new
    @proxy_model.setSourceModel @word_model
    @proxy_model.setDynamicSortFilter true
    
    @word_table_view.setModel @proxy_model
    @word_table_view.setColumnWidth 0, 150
    @word_table_view.horizontalHeader.setStretchLastSection true
    connect(@word_table_view, SIGNAL('customContextMenuRequested(QPoint)'), SLOT('customMenuRequested(QPoint)'))
    
    # Filter groups
    @rec_button_group = window.findChild Qt::ButtonGroup, "recAvaillableGroup"
    connect(@rec_button_group, SIGNAL('buttonClicked(QAbstractButton*)'), SLOT('recGroupBtnClicked(QAbstractButton*)'))
    @dia_button_group = window.findChild Qt::ButtonGroup, "diacriticGroup"    
    connect(@dia_button_group, SIGNAL('buttonClicked(QAbstractButton*)'), SLOT('diaGroupBtnClicked(QAbstractButton*)'))
    @dia_group_box = window.findChild Qt::GroupBox, "diaGroupBox"
    @rec_group_box = window.findChild Qt::GroupBox, "recGroupBox"
    
    # Timer for progress bar
    @timer = Qt::Timer.new
    @timer.setInterval(TIMER_INTERVAL)
    connect(@timer, SIGNAL('timeout()'), SLOT('onTimerTimeout()'))
    
    # Center window
    window.setGeometry(Qt::Style.alignedRect(Qt::LeftToRight, Qt::AlignCenter, window.size, $qApp.desktop.availableGeometry))
    
    # Display window
    window.show
  end
  
  slots 'onPlayBtnClicked()'
  slots 'onRecordBtnClicked()'
  slots 'onReloadBtnClicked()'
  slots 'onWordListClicked(QModelIndex)'
  slots 'onWordListDoubleClicked(QModelIndex)'
  slots 'onTimerTimeout()'
  
  def onPlayBtnClicked()
    word =  @word_model.original_data(@proxy_model.mapToSource(@word_table_view.selectedIndexes()[0]))
    diacritic = @word_model.diacritic(word)
    
    Process.detach Process.spawn("aplay wav/#{diacritic}/#{word}.wav")
  end
  
  def onRecordBtnClicked()
    @record_progress_bar.reset
    @time ||= Qt::Time.currentTime
    @time.start
    @timer.start
    
    word =  @word_model.original_data(@proxy_model.mapToSource(@word_table_view.selectedIndexes()[0]))
    diacritic = @word_model.diacritic(word)

    @record_pid = Process.spawn("arecord --file-type=wav --channels=1 --rate=16000 --format=S16_LE wav/#{diacritic}/#{word}.wav --duration=#{MAX_RECORD_TIME}")
  end
  
  def onReloadBtnClicked()
    # Repopulate list model
    @word_model = WordModel.new
    disableWindow
    Thread.new do
      @proxy_model.setSourceModel @word_model
      enableWindow
    end
  end
  
  def onWordListClicked(index)
    @record_button.setDisabled(false)
    if !@timer.isActive
      @record_progress_bar.setValue @record_progress_bar.minimum
    end

    if @word_model.exists? @proxy_model.mapToSource(index)
      @play_button.setDisabled false
    else
      @play_button.setDisabled true
    end
  end
  
  def onWordListDoubleClicked(index)
    if @word_model.exists? @proxy_model.mapToSource(index)
      onPlayBtnClicked()
    end
  end
  
  def onTimerTimeout
    @record_progress_bar.setValue( (@time.elapsed > @record_progress_bar.maximum) ? @record_progress_bar.maximum : (@time.elapsed) )
    if @time.elapsed > MAX_RECORD_TIME
      @timer.stop
      system("kill #{@record_pid}")
    end
  end
  
  slots 'recGroupBtnClicked(QAbstractButton*)'
  slots 'diaGroupBtnClicked(QAbstractButton*)'
  
  def recGroupBtnClicked(button)
    @filter = @proxy_model.filter
    case button.text
    when tr("All")
      @filter[:record_availability] = 'all'
    when tr("Recorded")
      @filter[:record_availability] = 'recorded'
    when tr("N/A")
      @filter[:record_availability] = 'n\/a'
    end
    
    disableWindow
    Thread.new do
      @proxy_model.setFilter @filter
      enableWindow
    end
  end
  
  def diaGroupBtnClicked(button)
    @filter = @proxy_model.filter
    case button.text
    when tr("Unmarked")
      if button.checked
        @filter[:diacritics] << 'unmarked'
      else
        @filter[:diacritics].delete 'unmarked'
      end
    when tr("Acute")
      if button.checked
        @filter[:diacritics] << 'acute'
      else
        @filter[:diacritics].delete 'acute'
      end
    when tr("Grave")
      if button.checked
        @filter[:diacritics] << 'grave'
      else
        @filter[:diacritics].delete 'grave'
      end
    when tr("Hook")
      if button.checked
        @filter[:diacritics] << 'hook'
      else
        @filter[:diacritics].delete 'hook'
      end
    when tr("Tilde")
      if button.checked
        @filter[:diacritics] << 'tilde'
      else
        @filter[:diacritics].delete 'tilde'
      end
    when tr("Dot")
      if button.checked
        @filter[:diacritics] << 'dot'
      else
        @filter[:diacritics].delete 'dot'
      end
    end
    
    disableWindow
    Thread.new do
      @proxy_model.setFilter @filter
      enableWindow
    end
  end
  
  slots 'customMenuRequested(QPoint)'
  def customMenuRequested(position)
    # Proxy to click event
    word_idx = @word_table_view.indexAt(position)
    onWordListClicked(word_idx)
    
    @menu ||= begin
      menu = Qt::Menu.new
      menu.addAction @action_play
      menu.addAction @action_record
      menu
    end
    
    if @word_model.exists? @proxy_model.mapToSource(word_idx)
      @action_play.setDisabled false
    else
      @action_play.setDisabled true
    end
    @menu.exec(Qt::Cursor.pos)
  end
  
  private
  def disableWindow
    @word_table_view.setDisabled true
    @dia_group_box.setDisabled true
    @rec_group_box.setDisabled true
    Qt::Application.setOverrideCursor Qt::Cursor.new(Qt::WaitCursor)
  end
  
  def enableWindow
    @word_table_view.setDisabled false
    @dia_group_box.setDisabled false
    @rec_group_box.setDisabled false
    Qt::Application.restoreOverrideCursor
  end
end

app = RecordApp.new ARGV
app.exec()