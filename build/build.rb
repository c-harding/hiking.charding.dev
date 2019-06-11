#!/usr/bin/env ruby

exit($?) unless system(`build/html.rb`)
exit($?) unless system(`build/css.rb`)
