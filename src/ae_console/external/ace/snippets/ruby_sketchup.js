ace.define('ace/snippets/ruby_sketchup', ['require', 'exports', 'module' ], function(require, exports, module) {

// Warning! The ace SnippetManager.parseSnippetFile (ext-language_tools line 646)
// requires tab characters before the snippets. Make sure not to save tabs to spaces.

exports.snippetText = "########################################\n\
# Ruby snippets - for SketchUp, see below #\n\
########################################\n\
\n\
snippet yields\n\
	:yields: ${1:arguments}\n\
snippet begin\n\
	begin\n\
	  ${3}\n\
	rescue ${1:Exception} => ${2:e}\n\
	end\n\
\n\
snippet require\n\
	require \"${1: }\"${2: }\n\
snippet case\n\
	case ${1:object}\n\
	when ${2:condition}\n\
	  ${3}\n\
	end\n\
snippet when\n\
	when ${1:condition}\n\
	  ${2}\n\
snippet def method\n\
	def ${1:method_name}\n\
	  ${2}\n\
	end\n\
snippet if\n\
	if ${1:condition}\n\
	  ${2}\n\
	end\n\
snippet if else\n\
	if ${1:condition}\n\
	  ${2}\n\
	else\n\
	  ${3}\n\
	end\n\
snippet elsif\n\
	elsif ${1:condition}\n\
	  ${2}\n\
snippet unless\n\
	unless ${1:condition}\n\
	  ${2}\n\
	end\n\
snippet while\n\
	while ${1:condition}\n\
	  ${2}\n\
	end\n\
snippet for\n\
	for ${1:e} in ${2:c}\n\
	  ${3: }\n\
	end\n\
snippet until\n\
	until ${1:condition}\n\
	  ${2: }\n\
	end\n\
snippet class .. end\n\
	class ${1:ClassName}\n\
	  ${2}\n\
	end\n\
snippet class .. initialize .. end\n\
	class ${1:ClassName}\n\
	  def initialize(${2:args})\n\
	    ${3: }\n\
	  end\n\
	end\n\
snippet class .. < ParentClass .. initialize .. end\n\
	class ${1:ClassName} < ${2:ParentClass}\n\
	  def initialize(${3:args})\n\
	    ${4: }\n\
	  end\n\
	end\n\
snippet cla class << self .. end\n\
	class << ${1:self}\n\
	  ${2}\n\
	end\n\
snippet mod module .. end\n\
	module ${1:ModuleName}\n\
	  ${2}\n\
	end\n\
snippet mod module .. module_function .. end\n\
	module ${1:ModuleName}\n\
	  module_function\n\
\n\
	  ${2}\n\
	end\n\
# attr_reader\n\
snippet attr_reader\n\
	attr_reader :${1:attr_names}\n\
# attr_writer\n\
snippet attr_writer\n\
	attr_writer :${1:attr_names}\n\
# attr_accessor\n\
snippet attr_accessor\n\
	attr_accessor :${1:attr_names}\n\
snippet attr_accessible\n\
	attr_protected :${1:attr_names}\n\
# def self.method\n\
snippet def self.method\n\
	def self.${1:class_method_name}\n\
	  ${2}\n\
	end\n\
# def method_missing\n\
snippet def method_missing\n\
	def method_missing(meth, *args, &block)\n\
	  ${1}\n\
	end\n\
snippet array\n\
	Array.new(${1:10}){ |${2:i}| ${3} }\n\
snippet hash\n\
	Hash.new{ |${1:hash}, ${2:key}| $1[$2] = ${3} }\n\
snippet dirname\n\
	File.dirname(__FILE__)\n\
snippet delete_if\n\
	delete_if{ |${1:e}| ${2: } }\n\
# downto(0){ |n| .. }\n\
snippet downto\n\
	downto(${1:0}){ |${2:n}| ${3: } }\n\
snippet step\n\
	step(${1:2}){ |${2:n}| ${3: } }\n\
snippet times\n\
	times{ |${1:n}| ${2: } }\n\
snippet upto\n\
	upto(${1:1.0/0.0}){ |${2:n}| ${3: } }\n\
snippet loop\n\
	loop{ ${1: } }\n\
snippet each\n\
	each{ |${1:e}| ${2} }\n\
snippet each_index\n\
	each_index{ |${1:i}| ${2: } }\n\
snippet each_key\n\
	each_key{ |${1:key}| ${2: } }\n\
snippet each_pair\n\
	each_pair{ |${1:name}, ${2:val}| ${3: } }\n\
snippet each_value\n\
	each_value{ |${1:val}| ${2: } }\n\
snippet each_with_index\n\
	each_with_index{ |${1:e}, ${2:i}| ${3: } }\n\
snippet inject\n\
	inject(${1:init}){ |${2:mem}, ${3:var}| ${4: } }\n\
snippet map\n\
	map{ |${1:e}| ${2: } }\n\
snippet sort\n\
	sort{ |a, b| ${1: } }\n\
snippet sort_by\n\
	sort_by{ |${1:e}| ${2: } }\n\
snippet collect\n\
	collect{ |${1:e}| ${2: } }\n\
snippet detect\n\
	detect{ |${1:e}| ${2: } }\n\
snippet fetch\n\
	fetch(${1:name}){ |${2:key}| ${3: } }\n\
snippet find\n\
	find{ |${1:e}| ${2: } }\n\
snippet find_all\n\
	find_all{ |${1:e}| ${2: } }\n\
snippet grep\n\
	grep(${1:/pattern/}){ |${2:match}| ${3: } }\n\
snippet sub\n\
	sub(${1:/pattern/}){ |${2:match}| ${3: } }\n\
snippet scan\n\
	scan(${1:/pattern/}){ |${2:match}| ${3: } }\n\
snippet max\n\
	max{ |a, b| ${1: } }\n\
snippet min\n\
	min{ |a, b| ${1: } }\n\
snippet reject\n\
	reject{ |${1:e}| ${2: } }\n\
snippet select\n\
	select{ |${1:e}| ${2: } }\n\
snippet tc\n\
	require \"test/unit\"\n\
\n\
	require \"${1:library_file_name}\"\n\
\n\
	class Test${2:$1} < Test::Unit::TestCase\n\
	  def test_${3:case_name}\n\
	    ${4}\n\
	  end\n\
	end\n\
# Benchmark.bmbm do .. end\n\
snippet bm-\n\
	TESTS = ${1:10_000}\n\
	Benchmark.bmbm do |results|\n\
	  ${2}\n\
	end\n\
snippet rep\n\
	results.report(\"${1:name}:\") { TESTS.times { ${2} }}\n\
# singleton_class()\n\
snippet singelton class\n\
	class << self; self end\n\
# block\n\
snippet block\n\
	{ |${1:var}| ${2} }\n\
snippet begin\n\
	begin\n\
	  raise 'A test exception.'\n\
	rescue Exception => e\n\
	  puts e.message\n\
	  puts e.backtrace.inspect\n\
	else\n\
	  # other exception\n\
	ensure\n\
	  # always executed\n\
	end\n\
\n\
# SketchUp snippets #\n\
########################################\n\
snippet mod\n\
	mod = Sketchup.active_model\n\
snippet sel\n\
	sel = Sketchup.active_model.selection\n\
snippet operation\n\
	mod.start_operation(\"${1:Operation name}\", true)\n\
	  ${2}\n\
	mod.commit_operation\n\
snippet vert2point\n\
	vertices.map{ |v| v.position }\n\
snippet uv\n\
	uvh = ${1:face}.get_UVHelper(true, true)\n\
	uv = uvh.get_front_UVQ(${2:point})\n\
	uv.x /= uv.z; uv.y /= uv.z; uv.z = 1\n\
snippet web\n\
	w = UI::WebDialog.new(\"${1:Title}\")\n\
	w.set_url = \"${2:http://www.wikipedia.org}\"\n\
	w.show\n\
snippet webdialog\n\
	${1:dialog} = UI::WebDialog.new(\"${2:titel}\", false, \"${3:pref_key}\", ${4:width}, ${5:height}, ${6:x}, ${7:y}, true)\n\
snippet add_action_callback\n\
	${1:dialog}.add_action_callback{ |dlg|\n\
	  ${2}\n\
	}\n\
snippet menu\n\
	${1:command} = UI::Command.new(\"${2:Command Name}\") {\n\
	  ${3}\n\
	}\n\
	${1:command}.small_icon = \"${4:Path}\"\n\
	${1:command}.large_icon = \"${5:Description}\"\n\
	${1:command}.tooltip = \"${6:Description}\"\n\
	\n\
	UI.menu(\"Plugins\").add_item(${1:command})\n\
snippet loaded?\n\
	unless file_loaded?(__FILE__)\n\
	  ${1}\n\
	  file_loaded(__FILE__)\n\
	end\n\
snippet tool\n\
	class TestTool\n\
	  def initialize\n\
	    @ip = Sketchup::InputPoint.new\n\
	  end\n\
	  def draw(view)\n\
	    @ip.draw if @ip.valid?\n\
	  end\n\
	  def onLButtonDown(flags, x, y, view)\n\
	    @ip.pick(view, x, y)\n\
	  end\n\
	end\n\
	Sketchup.active_model.tools.select_tool(TestTool.new)\n\
";
exports.scope = "ruby_sketchup";

});
