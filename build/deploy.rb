#!/usr/bin/env ruby

exit($?.exitstatus) unless system('build/build.rb')

File.rename '.deploy.gitignore', '.gitignore'
