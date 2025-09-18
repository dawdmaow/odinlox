package main

import "core:fmt"
import "core:strings"

Token_Kind :: enum {
	// single-character tokens
	LEFT_PAREN,
	RIGHT_PAREN,
	LEFT_BRACE,
	RIGHT_BRACE,
	COMMA,
	DOT,
	MINUS,
	PLUS,
	SEMICOLON,
	SLASH,
	STAR,

	// one or two character tokens
	BANG,
	BANG_EQUAL,
	EQUAL,
	EQUAL_EQUAL,
	GREATER,
	GREATER_EQUAL,
	LESS,
	LESS_EQUAL,

	// literals
	IDENTIFIER,
	STRING,
	NUMBER,

	// keywords
	AND,
	CLASS,
	ELSE,
	FALSE,
	FOR,
	FUN,
	IF,
	NIL,
	OR,
	PRINT,
	RETURN,
	SUPER,
	THIS,
	TRUE,
	VAR,
	WHILE,

	// other
	ERROR,
	EOF,
}

Token :: struct {
	kind:   Token_Kind,
	line:   int,
	lexeme: string,
}

Scanner :: struct {
	source:    string,
	i:         int,
	line:      int,
	had_error: bool,
}

scanner: Scanner

init_scanner :: proc(source: string) {
	scanner.source = source
	scanner.i = 0
	scanner.line = 1
	scanner.had_error = false
}

scanner_at_end :: proc() -> bool {
	return scanner.i >= len(scanner.source)
}

scanner_advance :: proc() -> byte {
	if !scanner_at_end() {
		scanner.i += 1
		return scanner.source[scanner.i - 1]
	}
	return 0
}

scanner_peek :: proc() -> byte {
	if scanner_at_end() do return 0
	return scanner.source[scanner.i]
}

scanner_peek_next :: proc() -> byte {
	if scanner.i + 1 >= len(scanner.source) do return 0
	return scanner.source[scanner.i + 1]
}

scanner_match :: proc(expected: byte) -> bool {
	if scanner_at_end() do return false
	if scanner.source[scanner.i] != expected do return false
	scanner.i += 1
	return true
}

make_token :: proc(kind: Token_Kind, start: int, end := scanner.i) -> Token {
	text := scanner.source[start:end]
	return Token{kind, scanner.line, text}
}

make_token_with_lexeme :: proc(kind: Token_Kind, lexeme: string) -> Token {
	return Token{kind, scanner.line, lexeme}
}

scanner_string :: proc() -> Token {
	start := scanner.i
	for scanner_peek() != '"' && !scanner_at_end() {
		if scanner_peek() == '\n' do scanner.line += 1
		scanner_advance()
	}

	if scanner_at_end() {
		return make_token_with_lexeme(.ERROR, "Unterminated string.")
	}

	assert(scanner_peek() == '"')
	scanner_advance()

	return make_token(.STRING, start, scanner.i - 1)
}

number_token :: proc() -> Token {
	start := scanner.i
	for is_digit(scanner_peek()) do scanner_advance()

	if scanner_peek() == '.' && is_digit(scanner_peek_next()) {
		scanner_advance() // consume the '.'
		for is_digit(scanner_peek()) do scanner_advance()
	}

	return make_token(.NUMBER, start)
}

identifier_token :: proc() -> Token {
	start := scanner.i
	for is_valid_identifier_char(scanner_peek()) do scanner_advance()

	text := scanner.source[start:scanner.i]
	kind := identifier_kind(text)
	return make_token_with_lexeme(kind, text)
}

identifier_kind :: proc(text: string) -> (result: Token_Kind) {
	switch text[0] {
	case 'a':
		if text == "and" do return .AND
	case 'c':
		if text == "class" do return .CLASS
	case 'e':
		if text == "else" do return .ELSE
	case 'f':
		if text == "false" do return .FALSE
		else if text == "for" do return .FOR
		else if text == "fun" do return .FUN
	case 'i':
		if text == "if" do return .IF
	case 'n':
		if text == "nil" do return .NIL
	case 'o':
		if text == "or" do return .OR
	case 'p':
		if text == "print" do return .PRINT
	case 'r':
		if text == "return" do return .RETURN
	case 's':
		if text == "super" do return .SUPER
	case 't':
		if text == "true" do return .TRUE
		if text == "this" do return .THIS
	case 'v':
		if text == "var" do return .VAR
	case 'w':
		if text == "while" do return .WHILE
	}
	return .IDENTIFIER
}

skip_whitespace :: proc() {
	for {
		switch scanner_peek() {
		case ' ', '\r', '\t':
			scanner_advance()
		case '\n':
			scanner.line += 1
			scanner_advance()
		case '/':
			if scanner_peek_next() == '/' {
				for scanner_peek() != '\n' && !scanner_at_end() do scanner_advance()
			} else {
				return
			}
		case:
			return
		}
	}
}

scan_token :: proc() -> Token {
	skip_whitespace()

	if scanner_at_end() do return make_token_with_lexeme(.EOF, "")

	start := scanner.i
	char := scanner_advance()

	if is_digit(char) {
		scanner.i = start // reset to beginning of number
		return number_token()
	}
	if is_letter(char) {
		scanner.i = start // reset to beginning of identifier
		return identifier_token()
	}

	switch char {
	case '(':
		return make_token(.LEFT_PAREN, start)
	case ')':
		return make_token(.RIGHT_PAREN, start)
	case '{':
		return make_token(.LEFT_BRACE, start)
	case '}':
		return make_token(.RIGHT_BRACE, start)
	case ';':
		return make_token(.SEMICOLON, start)
	case ',':
		return make_token(.COMMA, start)
	case '.':
		return make_token(.DOT, start)
	case '-':
		return make_token(.MINUS, start)
	case '+':
		return make_token(.PLUS, start)
	case '/':
		return make_token(.SLASH, start)
	case '*':
		return make_token(.STAR, start)
	case '!':
		return make_token(scanner_match('=') ? .BANG_EQUAL : .BANG, start)
	case '=':
		return make_token(scanner_match('=') ? .EQUAL_EQUAL : .EQUAL, start)
	case '<':
		return make_token(scanner_match('=') ? .LESS_EQUAL : .LESS, start)
	case '>':
		return make_token(scanner_match('=') ? .GREATER_EQUAL : .GREATER, start)
	case '"':
		return scanner_string()
	}

	return make_token_with_lexeme(.ERROR, fmt.aprintf("Unexpected character: {}", char))
}

is_digit :: proc(c: byte) -> bool {
	return c >= '0' && c <= '9'
}

is_letter :: proc(c: byte) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

// is_alphanumeric :: proc(c: byte) -> bool {
// 	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
// }

is_valid_identifier_char :: proc(c: byte) -> bool {
	return is_letter(c) || is_digit(c) || c == '_'
}

// peek :: proc(source: string, i: int) -> byte {
// 	if i < len(source) {
// 		return source[i]
// 	} else {
// 		return 0
// 	}
// }

// tokenize :: proc(source: string) -> (result: [dynamic]Token, ok: bool) {
// 	result = make([dynamic]Token)
// 	ok = true

// 	i := 0
// 	line := 1

// 	for i < len(source) {
// 		char := source[i]

// 		switch char {
// 		case '\n':
// 			line += 1
// 			i += 1
// 		case ' ', '\t', '\r':
// 			i += 1
// 		case '(':
// 			append(&result, Token{.LEFT_PAREN, line, "("})
// 			i += 1
// 		case ')':
// 			append(&result, Token{.RIGHT_PAREN, line, ")"})
// 			i += 1
// 		case '{':
// 			append(&result, Token{.LEFT_BRACE, line, "{"})
// 			i += 1
// 		case '}':
// 			append(&result, Token{.RIGHT_BRACE, line, "}"})
// 			i += 1
// 		case ',':
// 			append(&result, Token{.COMMA, line, ","})
// 			i += 1
// 		case '.':
// 			append(&result, Token{.DOT, line, "."})
// 			i += 1
// 		case '-':
// 			append(&result, Token{.MINUS, line, "-"})
// 			i += 1
// 		case '+':
// 			append(&result, Token{.PLUS, line, "+"})
// 			i += 1
// 		case ';':
// 			append(&result, Token{.SEMICOLON, line, ";"})
// 			i += 1
// 		case '*':
// 			append(&result, Token{.STAR, line, "*"})
// 			i += 1
// 		case '/':
// 			if peek(source, i + 1) == '/' {
// 				// Comment - skip to end of line
// 				i += 2
// 				for i < len(source) && source[i] != '\n' {
// 					i += 1
// 				}
// 			} else {
// 				append(&result, Token{.SLASH, line, "/"})
// 				i += 1
// 			}
// 		case '!':
// 			if peek(source, i + 1) == '=' {
// 				append(&result, Token{.BANG_EQUAL, line, "!="})
// 				i += 2
// 			} else {
// 				append(&result, Token{.BANG, line, "!"})
// 				i += 1
// 			}
// 		case '=':
// 			if peek(source, i + 1) == '=' {
// 				append(&result, Token{.EQUAL_EQUAL, line, "=="})
// 				i += 2
// 			} else {
// 				append(&result, Token{.EQUAL, line, "="})
// 				i += 1
// 			}
// 		case '>':
// 			if peek(source, i + 1) == '=' {
// 				append(&result, Token{.GREATER_EQUAL, line, ">="})
// 				i += 2
// 			} else {
// 				append(&result, Token{.GREATER, line, ">"})
// 				i += 1
// 			}
// 		case '<':
// 			if peek(source, i + 1) == '=' {
// 				append(&result, Token{.LESS_EQUAL, line, "<="})
// 				i += 2
// 			} else {
// 				append(&result, Token{.LESS, line, "<"})
// 				i += 1
// 			}
// 		case '"':
// 			i += 1
// 			sb := strings.builder_make()
// 			for i < len(source) && source[i] != '"' {
// 				strings.write_byte(&sb, source[i])
// 				i += 1
// 			}
// 			i += 1
// 			append(&result, Token{.STRING, line, strings.to_string(sb)})

// 		case:
// 			if is_digit(char) {
// 				// it must be a number
// 				sb := strings.builder_make()
// 				for i < len(source) && is_digit(source[i]) {
// 					strings.write_byte(&sb, source[i])
// 					i += 1
// 				}
// 				if i < len(source) && source[i] == '.' {
// 					i += 1
// 					for i < len(source) && is_digit(source[i]) {
// 						strings.write_byte(&sb, source[i])
// 						i += 1
// 					}
// 				}
// 				if i < len(source) && source[i] == '.' {
// 					i += 1
// 					for i < len(source) && is_digit(source[i]) {
// 						strings.write_byte(&sb, source[i])
// 						i += 1
// 					}
// 				}
// 				append(&result, Token{.NUMBER, line, strings.to_string(sb)})
// 			} else if is_alphanumeric(char) {
// 				// it must be either an identifier or a keyword
// 				sb := strings.builder_make()
// 				for i < len(source) && is_alphanumeric(source[i]) {
// 					strings.write_byte(&sb, source[i])
// 					i += 1
// 				}
// 				lexeme := strings.to_string(sb)
// 				kind := Token_Kind.IDENTIFIER
// 				switch lexeme[0] {
// 				case 't':
// 					if lexeme == "true" do kind = .TRUE
// 					else if lexeme == "this" do kind = .THIS
// 				case 'f':
// 					if lexeme == "false" do kind = .FALSE
// 					else if lexeme == "for" do kind = .FOR
// 					else if lexeme == "fun" do kind = .FUN
// 				case 'n':
// 					if lexeme == "nil" do kind = .NIL
// 				case 'i':
// 					if lexeme == "if" do kind = .IF
// 				case 'r':
// 					if lexeme == "return" do kind = .RETURN
// 				case 'v':
// 					if lexeme == "var" do kind = .VAR
// 				case 'w':
// 					if lexeme == "while" do kind = .WHILE
// 				case 's':
// 					if lexeme == "super" do kind = .SUPER
// 				case 'p':
// 					if lexeme == "print" do kind = .PRINT
// 				case 'c':
// 					if lexeme == "class" do kind = .CLASS
// 				case 'e':
// 					if lexeme == "else" do kind = .ELSE
// 				case 'o':
// 					if lexeme == "or" do kind = .OR
// 				case 'a':
// 					if lexeme == "and" do kind = .AND
// 				}
// 				token := Token{kind, line, lexeme}
// 				append(&result, token)
// 			} else {
// 				ok = false
// 				append(&result, Token{.ERROR, line, fmt.aprintf("Unexpected character: {}", char)})
// 				i += 1
// 			}
// 		}
// 	}

// 	append(&result, Token{.EOF, line, ""})
// 	return
// }
