Bộ công cụ và dữ liệu thu âm từ đơn tiếng việt
=========================

**Môi trường khuyến cáo: Ubuntu/Linux**

1. Script tải dữ liệu từ Wikitionary tiếng Việt: `wiktionary.rb`
  * Yêu cầu phần mềm: Ruby 1.9+, gem unicode, `sort`, `wc`
  * Chạy từ terminal: `$ ./wiktionary.rb`
  * Kết quả: `words.txt`
  
2. Chương trình hỗ trợ thu âm từ đơn tiếng việt: `record.rb`
  * Yêu cầu phần mềm: Ruby 1.9+, ruby-qt4, ruby-qt4-uitools, alsa-utils (`arecord` và `aplay`), gem i18n
  * Yêu cầu dữ liệu: tập tin `words.txt`, `words-blacklist.txt` (mỗi dòng chứa một từ sai chính tả, vô nghĩa hoặc trùng lặp)
  * Chạy từ terminal:`$ ./record.rb` hoặc mở trực tiếp
3. Dữ liệu thu âm: 
  * Người nói `lephuong`: 6221 từ, giọng bắc
