import os
import regex

fn main(){
	naml := os.read_file('test.naml') or { panic(err) }
	token_stream := tokenize(naml)
	root_node := parse_naml(token_stream)
	println(root_node)
}

struct NamlBlock {
	identifier string
mut:
	values []&NamlValue
	children []&NamlBlock
}

struct NamlValue {
	identifier string
	value_string string
	kind ValueKind
}

enum ValueKind {
	string
	integer
	double
	boolean
}

struct ParserState {
	token_stream []&Token
mut:
	index int
	current_token &Token
	root_block &NamlBlock
	block_stack []&NamlBlock
}

fn parse_naml(token_stream []&Token) &NamlBlock {
	root_block := &NamlBlock{
		identifier: '\$root'
		children: []&NamlBlock{}
		values: []&NamlValue{}
	}

	if token_stream.len == 0 {
		return root_block
	}

	mut block_stack := [root_block]

	mut parser := &ParserState{
		token_stream: token_stream
		index: 0
		current_token: token_stream[0]
		root_block: root_block
		block_stack: block_stack
	}

	parser.parse_root()

	return parser.root_block
}

fn (mut p ParserState) match_token(kind TokenKind){
	if p.current_token.kind == kind {
		p.current_token = p.next_token(kind)
		return
	}
	panic('unexpected token $p.current_token, expected $kind')
}

fn (mut p ParserState) add_block_child(child &NamlBlock) {
	mut current_block := p.block_stack.last()
	current_block.children << child
}

fn (mut p ParserState) add_block_value(child &NamlValue) {
	mut current_block := p.block_stack.last()
	current_block.values << child
}

fn (mut p ParserState) is_eof() bool {
	return p.token_stream.len <= p.index+1
}

fn (mut p ParserState) next_token(kind TokenKind) &Token {
	if !p.is_eof() {
		p.index++
		return p.token_stream[p.index]
	}

	panic('unexpected end of token stream, expected $kind')
}

//literal = string | double | integer | boolean
fn (mut p ParserState) parse_literal(identifier string) {
	value_string := p.current_token.text

	match true {
		p.current_token.kind == .string {
			p.match_token(.string)
			p.add_block_value(&NamlValue{
				identifier: identifier
				value_string: value_string
				kind: .string
			})
		}

		p.current_token.kind == .double {
			p.match_token(.double)
			p.add_block_value(&NamlValue{
				identifier: identifier
				value_string: value_string
				kind: .double
			})
		}

		p.current_token.kind == .integer {
			p.match_token(.integer)
			p.add_block_value(&NamlValue{
				identifier: identifier
				value_string: value_string
				kind: .integer
			})
		}

		p.current_token.kind == .boolean {
			p.match_token(.boolean)
			p.add_block_value(&NamlValue{
				identifier: identifier
				value_string: value_string
				kind: .boolean
			})
		}

		else {
			panic('unexpected token $p.current_token')
		}
	}
}

//value = identifier value_content
fn (mut p ParserState) parse_value() {
	identifier := p.current_token.text
	p.match_token(.identifier)
	p.parse_value_content(identifier)
}

//value_content = literal | block
fn (mut p ParserState) parse_value_content(identifier string) {
	if p.current_token.kind == .block_open {
		p.parse_block(identifier)
	} else {
		p.parse_literal(identifier)
	}
}

//block = block_open valueList
fn (mut p ParserState) parse_block(identifier string) {
	p.match_token(.block_open)

	mut children := []&NamlBlock{}
	mut values := []&NamlValue{}
	mut block := &NamlBlock{
		identifier: identifier
		children: children
		values: values
	}

	p.add_block_child(block)
	p.block_stack << block

	p.parse_value_list()

	p.block_stack.pop()
}

//valueList = eof | } | (value valueList)
fn (mut p ParserState) parse_value_list() {
	if p.is_eof() {
		return
	} else if p.current_token.kind == .block_close {
		p.match_token(.block_close)
		return
	} else {
		p.parse_value()
		p.parse_value_list()
	}
}

//root = eof | valueList
fn (mut p ParserState) parse_root() {
	if p.is_eof() {
		return
	} else {
		p.parse_value_list()
	}
}

enum TokenKind {
	identifier
	block_open
	block_close
	assignment
	new_line
	white_space
	integer
	double
	boolean
	string
}

struct Token {
	text string
	kind TokenKind
	skip bool
	line int
	row int
}

fn tokenize(fileContent string) []&Token {
	tokenizer_functions := [
		tokenize_boolean,
		tokenize_block_open,
		tokenize_block_close,
		tokenize_assignment,
		tokenize_new_line,
		tokenize_identifier,
		tokenize_white_space,
		tokenize_double,
		tokenize_integer,
		tokenize_string
	]

	mut token_stream := []&Token{}

	mut current_index := 0
	mut current_line := 0
	mut current_col := 0

	for current_index < fileContent.len {
		mut tokenized := false

		for tokenizer_function in tokenizer_functions {
			if token := tokenizer_function(fileContent[current_index..], current_line, current_col) {
				token_len := token.text.len
				current_index += token_len
				current_col += token_len
				
				if token.kind == .new_line {
					current_line++
					current_col = 0
				}

				if !token.skip {
					token_stream << token
				}

				tokenized = true
				break
			}
		}

		if !tokenized {
			near_end_index := current_index + min(50, fileContent.len - current_index)

			panic('tokenization failed at line: $current_line, col: $current_col near: \'${fileContent[current_index..near_end_index]}\'')
		}
	}

	return token_stream
}

fn min(a int, b int) int {
	if a < b {
		return a
	}
	return b
}


fn tokenize_pattern(input string, pattern string, kind TokenKind, currentLine int, currentCol int, skip bool) ?&Token {
	mut re := regex.regex_opt('^$pattern') or { panic(err) }
	start, end := re.match_string(input)

	if start >= 0 {
		return &Token{
			text: input[start..end]
			kind: kind
			line: currentLine
			row: currentCol
			skip: skip
		}
	}

	return none
}

fn tokenize_white_space(input string, currentLine int, currentCol int) ?&Token {
	return tokenize_pattern(input, '\\s+', .white_space, currentLine, currentCol, true)
}

fn tokenize_identifier(input string, currentLine int, currentCol int) ?&Token {
	return tokenize_pattern(input, '[a-zA-Z]+', .identifier, currentLine, currentCol, false)
}

fn tokenize_double(input string, currentLine int, currentCol int) ?&Token {
	return tokenize_pattern(input, '(\\d+\\.\\d+)|(\\.\\d+)|(\\d+\\.)', .double, currentLine, currentCol, false)
}

fn tokenize_integer(input string, currentLine int, currentCol int) ?&Token {
	return tokenize_pattern(input, '\\d+', .integer, currentLine, currentCol, false)
}

fn tokenize_boolean(input string, currentLine int, currentCol int) ?&Token {
	return tokenize_pattern(input, 'y|n', .boolean, currentLine, currentCol, false)
}

fn tokenize_string(input string, currentLine int, currentCol int) ?&Token {
	return tokenize_pattern(input, '".*"', .string, currentLine, currentCol, false)
}

fn tokenize_single_character(input string, character string, kind TokenKind, currentLine int, currentCol int, skip bool) ?&Token {
	first_character := input[..1]

	if first_character == character {
		return &Token{
			text: first_character
			kind: kind
			line: currentLine
			row: currentCol
			skip: skip
		}
	}

	return none
}

fn tokenize_block_open(input string, currentLine int, currentCol int) ?&Token {
	return tokenize_single_character(input, "{", .block_open, currentLine, currentCol, false)
}

fn tokenize_block_close(input string, currentLine int, currentCol int) ?&Token {
	return tokenize_single_character(input, "}", .block_close, currentLine, currentCol, false)
}

fn tokenize_assignment(input string, currentLine int, currentCol int) ?&Token {
	return tokenize_single_character(input, "=", .assignment, currentLine, currentCol, true)
}

fn tokenize_new_line(input string, currentLine int, currentCol int) ?&Token {
	return tokenize_single_character(input, "\n", .new_line, currentLine, currentCol, true)
}