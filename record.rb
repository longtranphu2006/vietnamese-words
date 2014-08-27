#!/usr/bin/env ruby
# encoding: utf-8

require 'Qt4'
require 'qtuitools'
require 'i18n'
require 'thread'

I18n.load_path += Dir["./*.po"]
I18n.enforce_available_locales = true
I18n::Backend::Simple.include(I18n::Backend::Gettext)
I18n.default_locale = :vi

class WordModel < Qt::AbstractTableModel
  def initialize(recorder, parent = nil)
    super parent    
    
    populateWords
    self.recorder = recorder
  end
  
  def populateWords
    @words = open("words.txt").read.split("\n")
    @blacklist = open("words-blacklist.txt").read.split("\n")
    @words.reject!{ |w| @blacklist.include? w }
    @diacritics = @words.map{|w| diacritic(w)}
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
        Qt::Variant.new(exists?(index) ? I18n.t("Recorded") : I18n.t("N/A"))
      when 1
        Qt::Variant.new I18n.t(@diacritics[index.row].capitalize)
      when 2
        Qt::Variant.new @words[index.row]
      when 3
        Qt::Variant.new "wav/#{recorder}/#{@diacritics[index.row]}/#{@words[index.row]}.wav"
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
        Qt::Variant.new [I18n.t("Availability"), I18n.t("Diacritic"), I18n.t("Word"), I18n.t("Path")][section]
      else
        super
      end
    else
      Qt::Variant.new
    end
  end

  def exists?(index)
    File.exists? "wav/#{recorder}/#{diacritic(original_data(index))}/#{original_data(index)}.wav"
  end

  def recorder
    @recorder
  end

  def recorder=(new_recorder)
    @recorder = new_recorder

    # Init word directories
    ["wav", "wav/#{recorder}/unmarked", "wav/#{recorder}/acute", "wav/#{recorder}/grave", "wav/#{recorder}/hook", "wav/#{recorder}/tilde", "wav/#{recorder}/dot"].each do |dir|
      if !Dir.exists? dir
        Dir.mkdir dir
      end
    end
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
      availability_valid = sourceModel.data(availability_idx).toString.force_encoding('utf-8') == filter[:record_availability]
    end

    # Filter by diacritic
    diacritic_valid = (filter[:diacritics].map{|d| I18n.t(d.capitalize)}.include?(sourceModel.data(diacritic_idx).toString.force_encoding('utf-8')))

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
  MAX_RECORD_TIME = 700

  def initialize(argv)
    super argv
    
    # Set icon
    self.setWindowIcon Qt::Icon.fromTheme("media-record")

    # Load translation
    translator = Qt::Translator.new
    translator.load(Qt::Locale.system, "record", ".", ".", ".qm")
    installTranslator translator

    # Load UI
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
    @replay_check_box       = window.findChild Qt::CheckBox, "replayCheckBox"
    @recorder_combo_box     = window.findChild Qt::ComboBox, "recorderComboBox"
    @recorder_line_edit     = window.findChild Qt::LineEdit, "recorderLineEdit"
    @add_recorder_button    = window.findChild Qt::PushButton, "addRecorderButton"

    # Set record time to progress bar
    @record_progress_bar.setMaximum MAX_RECORD_TIME

    # Populate recorders
    Dir['wav/*'].reject{|node| !File.directory?(node)}.each do |dir|
      @recorder_combo_box.addItem File.basename(dir)
    end

    # Connect children signals
    connect(@play_button, SIGNAL('clicked()'), SLOT('onPlayBtnClicked()'))
    connect(@record_button, SIGNAL('clicked()'), SLOT('onRecordBtnClicked()'))
    connect(@reload_button, SIGNAL('clicked()'), SLOT('onReloadBtnClicked()'))
    connect(@add_recorder_button, SIGNAL('clicked()'), SLOT('onAddRecorderButtonClicked()'))
    connect(@action_play, SIGNAL('triggered()'), SLOT('onPlayBtnClicked()'))
    connect(@action_record, SIGNAL('triggered()'), SLOT('onRecordBtnClicked()'))
    connect(@word_table_view, SIGNAL('clicked(QModelIndex)'), SLOT('onWordListClicked(QModelIndex)'))
    connect(@word_table_view, SIGNAL('doubleClicked(QModelIndex)'), SLOT('onWordListDoubleClicked(QModelIndex)'))
    connect(@recorder_line_edit, SIGNAL('textChanged(QString)'), SLOT('onRecorderLineEditChanged(QString)'))
    connect(@recorder_line_edit, SIGNAL('returnPressed()'), SLOT('onRecorderLineEditReturned()'))
    connect(@recorder_combo_box, SIGNAL('currentIndexChanged(QString)'), SLOT('onRecorderComboBoxChanged(QString)'))

    # Setup model
    @proxy_model = WordFilterModel.new
    @proxy_model.setDynamicSortFilter true
    if !@recorder_combo_box.currentText.nil?
      @word_model  = WordModel.new @recorder_combo_box.currentText
      @proxy_model.setSourceModel @word_model
    end

    # Set up
    @word_table_view.setModel @proxy_model
    @word_table_view.setColumnWidth 0, 150
    @word_table_view.horizontalHeader.setStretchLastSection true
    connect(@word_table_view, SIGNAL('customContextMenuRequested(QPoint)'), SLOT('customMenuRequested(QPoint)'))
    connect(@word_table_view.selectionModel, SIGNAL('currentRowChanged(QModelIndex, QModelIndex)'), SLOT('onCurrentRowChanged(QModelIndex, QModelIndex)'))
    
    # Shortcut for table view
    @play_shortcut = Qt::Shortcut.new(Qt::KeySequence.new(Qt::Key_P), @word_table_view)
    connect(@play_shortcut, SIGNAL('activated()'), SLOT('onPlayBtnClicked()'));
    @play_shortcut_2 = Qt::Shortcut.new(Qt::KeySequence.new(Qt::Key_Return), @word_table_view)
    connect(@play_shortcut_2, SIGNAL('activated()'), SLOT('onPlayBtnClicked()'));
    @record_shortcut = Qt::Shortcut.new(Qt::KeySequence.new(Qt::Key_R), @word_table_view)
    connect(@record_shortcut, SIGNAL('activated()'), SLOT('onRecordBtnClicked()'));

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
    
    @filter_semaphore = Mutex.new
  end

  slots 'onPlayBtnClicked()'
  slots 'onRecordBtnClicked()'
  slots 'onReloadBtnClicked()'
  slots 'onWordListClicked(QModelIndex)'
  slots 'onCurrentRowChanged(QModelIndex, QModelIndex)'
  slots 'onWordListDoubleClicked(QModelIndex)'
  slots 'onRecorderLineEditChanged(QString)'
  slots 'onRecorderLineEditReturned()'
  slots 'onAddRecorderButtonClicked()'
  slots 'onRecorderComboBoxChanged(QString)'
  slots 'onTimerTimeout()'

  def onPlayBtnClicked()
    word =  @word_model.original_data(@proxy_model.mapToSource(@word_table_view.selectedIndexes()[0]))
    diacritic = @word_model.diacritic(word)
    recorder = @word_model.recorder

    Process.detach Process.spawn("aplay wav/#{recorder}/#{diacritic}/#{word}.wav")
  end

  def onRecordBtnClicked()
    @record_progress_bar.reset
    @time ||= Qt::Time.currentTime

    word =  @word_model.original_data(@proxy_model.mapToSource(@word_table_view.selectedIndexes()[0]))
    diacritic = @word_model.diacritic(word)
    recorder = @word_model.recorder
    
    sleep 0.1
    @record_pid = Process.spawn("arecord --file-type=wav --channels=1 --rate=16000 --format=S16_LE wav/#{recorder}/#{diacritic}/#{word}.wav")
    @time.start
    @timer.start
  end

  def onReloadBtnClicked()
    disableWindow
    Thread.new do
      # Repopulate list model
      @word_model.populateWords
      @proxy_model.reset
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
  
  def onCurrentRowChanged(current_index, previous_index)
    @record_button.setDisabled false
    if !@timer.isActive
      @record_progress_bar.setValue @record_progress_bar.minimum
    end

    if @word_model.exists? @proxy_model.mapToSource(current_index)
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

  def onRecorderLineEditChanged(text)
    if text.match /^[^ \/]+$/
      @add_recorder_button.setDisabled false
    else
      @add_recorder_button.setDisabled true
    end
  end

  def onRecorderLineEditReturned
    if @recorder_line_edit.text.match /^[^ \/]+$/
      onAddRecorderButtonClicked
    end
  end

  def onAddRecorderButtonClicked
    begin
      # Create new folder for recorder
      Dir.mkdir "wav" unless Dir.exists?("wav")
      Dir.mkdir "wav/#{@recorder_line_edit.text}"

      # Add new recorder into combobox
      @recorder_combo_box.addItem @recorder_line_edit.text

      # Clear line edit
      @recorder_line_edit.setText ""
    rescue
      # NOTE Nothing to handle here
    end
  end

  def onRecorderComboBoxChanged(recorder)
    if @word_model.nil?
      @word_model = WordModel.new recorder
      @proxy_model.setSourceModel @word_model
    else
      @word_model.recorder = recorder
      disableWindow
      Thread.new do
        @proxy_model.reset # Immediate update model
        enableWindow
      end
    end
  end

  def onTimerTimeout
    @record_progress_bar.setValue( (@time.elapsed > @record_progress_bar.maximum) ? @record_progress_bar.maximum : (@time.elapsed) )
    if @time.elapsed > MAX_RECORD_TIME
      @timer.stop
      system("kill #{@record_pid}")
      if @replay_check_box.isChecked
        onPlayBtnClicked()
      end
    end
  end

  slots 'recGroupBtnClicked(QAbstractButton*)'
  slots 'diaGroupBtnClicked(QAbstractButton*)'

  def recGroupBtnClicked(button)
    disableWindow
    Thread.new do
      @filter_semaphore.synchronize do
        @filter = @proxy_model.filter
        
        if button.text.force_encoding('utf-8') == I18n.t("All")
          @filter[:record_availability] = 'all'
        else
          @filter[:record_availability] = button.text.force_encoding('utf-8')
        end
        
        @proxy_model.setFilter @filter
      end
      
      enableWindow
    end
  end

  def diaGroupBtnClicked(button)
    @diacritic_map ||= {
      I18n.t("Unmarked") => 'unmarked',
      I18n.t("Acute") => 'acute',
      I18n.t("Grave") => 'grave',
      I18n.t("Hook") => 'hook',
      I18n.t("Tilde") => 'tilde',
      I18n.t("Dot") => 'dot'
    }

    disableWindow
    Thread.new do
      @filter_semaphore.synchronize do
        @filter = @proxy_model.filter
        
        unless @diacritic_map[button.text.force_encoding('utf-8')].nil?
          if button.checked
            @filter[:diacritics] << @diacritic_map[button.text.force_encoding('utf-8')]
          else
            @filter[:diacritics].delete @diacritic_map[button.text.force_encoding('utf-8')]
          end
        end

        @proxy_model.setFilter @filter
      end
      
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
    @reload_button.setDisabled true
    Qt::Application.setOverrideCursor Qt::Cursor.new(Qt::WaitCursor)
  end

  def enableWindow
    @word_table_view.setDisabled false
    @dia_group_box.setDisabled false
    @rec_group_box.setDisabled false
    @reload_button.setDisabled false
    Qt::Application.restoreOverrideCursor
  end
end

app = RecordApp.new ARGV
app.exec()
