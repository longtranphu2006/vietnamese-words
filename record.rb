#!/usr/bin/env ruby
# encoding: utf-8

require 'Qt4'
require 'qtuitools'

class WordModel < Qt::AbstractListModel
  def initialize(parent = nil)
    super parent
    @words = open("words.txt").read.split("\n")
    @blacklist = open("words-blacklist.txt").read.split("\n")
    @words.reject!{ |w| @blacklist.include? w }
    @tagged_words = @words.map{|w| "[#{diacritic(w)[0..2].upcase}] #{w}"}
    
    # Init word directories
    %w[wav wav/unmarked wav/acute wav/grave wav/hook wav/tilde wav/dot].each do |dir|
      if !Dir.exists? dir
        Dir.mkdir dir
      end
    end
  end
  
  def rowCount(parent = Qt::QModelIndex.new)
    @words.count
  end
  
  def data(index, role = Qt::DisplayRole)
    if role == Qt::DisplayRole
      if exists? index
        Qt::Variant.new "[REC] #{@tagged_words[index.row]}"
      else
        Qt::Variant.new "[N/A] #{@tagged_words[index.row]}"
      end
    else
      Qt::Variant.new
    end
  end
  
  def original_data(index)
    @words[index.row]
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

class RecordApp < Qt::Application
  TIMER_INTERVAL = 1
  MAX_RECORD_TIME = 500
  
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
    @record_progress_bar    = window.findChild Qt::ProgressBar, "recordProgressBar"
    @word_list_view         = window.findChild Qt::ListView, "wordListView"
    @word_count_label       = window.findChild Qt::Label, "wordCountLabel"
    
    # Set record time to progress bar
    @record_progress_bar.setMaximum MAX_RECORD_TIME
    
    # Connect children signals
    connect(@play_button, SIGNAL('clicked()'), SLOT('onPlayBtnClicked()'))
    connect(@record_button, SIGNAL('clicked()'), SLOT('onRecordBtnClicked()'))
    connect(@word_list_view, SIGNAL('clicked(QModelIndex)'), SLOT('onWordListClicked(QModelIndex)'))
    connect(@word_list_view, SIGNAL('doubleClicked(QModelIndex)'), SLOT('onWordListDoubleClicked(QModelIndex)'))
    
    # Assign model
    @word_list_model        = WordModel.new
    @proxy_model = Qt::SortFilterProxyModel.new
    @proxy_model.setSourceModel @word_list_model
    @proxy_model.setDynamicSortFilter true
    @word_list_view.setModel @proxy_model
    
    # Filters
    @filter = {
      record_availability: 'all',
      diacritics: ['unmarked', 'acute', 'grave', 'hook', 'tilde', 'dot']
    }
    filter
    
    # Filter groups
    @rec_button_group = window.findChild Qt::ButtonGroup, "recAvaillableGroup"
    connect(@rec_button_group, SIGNAL('buttonClicked(QAbstractButton*)'), SLOT('recGroupBtnClicked(QAbstractButton*)'))
    @dia_button_group = window.findChild Qt::ButtonGroup, "diacriticGroup"    
    connect(@dia_button_group, SIGNAL('buttonClicked(QAbstractButton*)'), SLOT('diaGroupBtnClicked(QAbstractButton*)'))
    
    # Timer for progress bar
    @timer = Qt::Timer.new
    @timer.setInterval(TIMER_INTERVAL)
    connect(@timer, SIGNAL('timeout()'), SLOT('onTimerTimeout()'))
    
    # Center window
    window.setGeometry(Qt::Style.alignedRect(Qt::LeftToRight, Qt::AlignCenter, window.size, $qApp.desktop.availableGeometry))
    
    # Display window
    window.show
  end
  
  def filter
    # Build regexp
    case @filter[:record_availability]
    when 'all'
      regexp = '\[(' + @filter[:diacritics].map{|d| d[0..2].upcase}.join("|") + ')\]'
    when 'recorded'
      regexp = '\[REC\] \[(' + @filter[:diacritics].map{|d| d[0..2].upcase}.join("|") + ')\]'
    when 'na'
      regexp = '\[N\/A\] \[(' + @filter[:diacritics].map{|d| d[0..2].upcase}.join("|") + ')\]'
    end
    
    @word_list_view.setDisabled true
    @proxy_model.setFilterRegExp regexp
    @word_list_view.setDisabled false
    
    @word_count_label.setText "#{@proxy_model.rowCount} word(s)"
  end
  
  slots 'onPlayBtnClicked()'
  slots 'onRecordBtnClicked()'
  slots 'onWordListClicked(QModelIndex)'
  slots 'onWordListDoubleClicked(QModelIndex)'
  slots 'onTimerTimeout()'
  
  def onPlayBtnClicked()
    word =  @word_list_model.original_data(@proxy_model.mapToSource(@word_list_view.selectedIndexes()[0]))
    diacritic = @word_list_model.diacritic(word)
    
    Process.detach Process.spawn("aplay wav/#{diacritic}/#{word}.wav")
  end
  
  def onRecordBtnClicked()
    @record_progress_bar.reset
    @time ||= Qt::Time.currentTime
    @time.start
    @timer.start
    
    word =  @word_list_model.original_data(@proxy_model.mapToSource(@word_list_view.selectedIndexes()[0]))
    diacritic = @word_list_model.diacritic(word)

    @record_pid = Process.spawn("arecord --file-type=wav --channels=1 --rate=16000 --format=S16_LE wav/#{diacritic}/#{word}.wav --duration=#{MAX_RECORD_TIME}")
  end
  
  def onWordListClicked(index)
    @record_button.setDisabled(false)

    if @word_list_model.exists? index
      @play_button.setDisabled false
    else
      @play_button.setDisabled true
    end
  end
  
  def onWordListDoubleClicked(index)
    if @word_list_model.exists? @proxy_model.mapToSource(index)
      onPlayBtnClicked()
    else
      onRecordBtnClicked()
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
    case button.text
    when tr("All")
      @filter[:record_availability] = 'all'
    when tr("Recorded")
      @filter[:record_availability] = 'recorded'
    when tr("N/A")
      @filter[:record_availability] = 'na'
    end
    
    filter
  end
  
  def diaGroupBtnClicked(button)
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
    
    filter
  end
end

app = RecordApp.new ARGV
app.exec()