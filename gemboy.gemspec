# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = 'gemboy'
  spec.version = '0.1.0'
  spec.authors = ['ABK']

  spec.summary = 'A Game Boy DMG-01 emulator written in Ruby'
  spec.description = 'A Ruby Game Boy (DMG-01) emulator using SDL2'
  spec.homepage = 'https://github.com/kaderate/gemboy'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.3'

  spec.metadata = {
    'allowed_push_host' => 'https://none.invalid', # local builds only, blocks `gem push`
    'source_code_uri' => spec.homepage,
    'rubygems_mfa_required' => 'true'
  }

  spec.files = Dir[
    'lib/**/*.rb',
    'assets/fonts/*.ttf',
    'assets/fonts/LICENSE-Inter.txt',
    'LICENSE',
    'README.md'
  ]
  spec.bindir = 'bin'
  spec.executables = ['gemboy']
  spec.require_paths = ['lib']

  spec.add_dependency 'logger', '~> 1.6'
  spec.add_dependency 'sdl2-bindings', '~> 0.2'
end
