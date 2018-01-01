require 'bundler/gem_tasks'
require 'rake/testtask'
require 'zip'
require 'pathname'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.libs << 'src'
  t.test_files = FileList['test/**/*_test.rb']
end

task :build_rbz do
  # Get the version
  project_name = 'ae_console'
  load(File.expand_path("../src/#{project_name}/version.rb", __FILE__))
  version = AE::ConsolePlugin::VERSION
  # Configuration
  files_to_exclude = %w{
    ae_console/images/icon_54.png
    ae_console/images/icon_60.png
    ae_console/images/icon_64.png
    ae_console/images/icon_128.png
    ae_console/images/icon.draft.svg
    ae_console/images/redo.png
    ae_console/images/redo.svg
    ae_console/images/icon_alternative.draft.svg
    ae_console/external/ace/worker-xquery.js
    ae_console/external/bootstrap/css/theme.css.map
    ae_console/external/bootstrap/css/bootstrap-theme.css.map
  }
  # Compressing
  create_zip_archive("#{project_name}_#{version}.rbz", 'src', include: '**/*', exclude: files_to_exclude)
end

def create_zip_archive(zip_filename, root_dir, include: [], exclude: [])
  root_dir = File.expand_path(root_dir)
  files_to_include = Dir.glob(File.expand_path(File.join(root_dir, include)))
  files_to_exclude = exclude.map{ |filename|
    filename = File.expand_path(File.join(root_dir, filename))
    (File.directory?(filename)) ? Dir.glob(filename+'/') : filename
  }.flatten
  
  Zip::File.open(zip_filename, Zip::File::CREATE) do |zip_file|
    files_to_include.each{ |filename|
      unless files_to_exclude.include?(filename)
        zipped_filename = Pathname.new(filename).relative_path_from(Pathname.new(root_dir))
        zip_file.add(zipped_filename, filename)
      end
    }
  end
end

task :default => :test
