#!/usr/bin/env ruby

exit($?.exitstatus) unless system('build/html.rb')
exit($?.exitstatus) unless system('build/css.rb')
