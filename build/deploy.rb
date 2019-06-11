#!/usr/bin/env ruby

exit($?.exitstatus) unless system('build/build.rb')
exit($?.exitstatus) unless system('build/rebuild_facebook_previews.rb')

File.rename '.deploy.gitignore', '.gitignore'
