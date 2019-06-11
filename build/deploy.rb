#!/usr/bin/env ruby

exit($?) unless system(`build/build.rb`)
exit($?) unless system(`build/rebuild_facebook_previews.rb`)

File.rename '.deploy.gitignore', '.gitignore'
