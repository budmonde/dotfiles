" Vim syntax file
" Language: llmlog (LLM chat log viewer output)
" Extends markdown syntax with llmlog-specific elements

if exists("b:current_syntax")
  finish
endif

" Enable syntax highlighting for common languages in fenced code blocks
" Must be set before loading markdown syntax
if !exists('g:markdown_fenced_languages')
  let g:markdown_fenced_languages = ['python', 'bash', 'sh', 'javascript', 'js=javascript', 'typescript', 'ts=typescript', 'json', 'yaml', 'lua', 'vim', 'sql', 'html', 'css', 'go', 'rust', 'c', 'cpp']
endif

" Load markdown syntax as base
runtime! syntax/markdown.vim
unlet! b:current_syntax

" Separator lines (━━━━━)
syn match llmlogSeparator /^━\+$/

" User header
syn match llmlogUserHeader /^USER │ .\+$/ contains=llmlogUserRole,llmlogTimestamp
syn match llmlogUserRole /^USER/ contained

" Assistant header
syn match llmlogAssistantHeader /^ASSISTANT │ .\+$/ contains=llmlogAssistantRole,llmlogTimestamp
syn match llmlogAssistantRole /^ASSISTANT/ contained

" Timestamp (after │)
syn match llmlogTimestamp /│ \zs\d\{4}-\d\{2}-\d\{2} \d\{2}:\d\{2}:\d\{2}/ contained

" Tool call summary [Tool: name]
syn match llmlogToolSummary /\[Tool: [^\]]\+\]/ contains=llmlogToolName
syn match llmlogToolName /Tool: \zs[^\]]\+/ contained

" Tool call expanded (fold markers)
syn region llmlogToolBlock start=/^{{{ Tool:/ end=/^}}}$/ fold contains=llmlogToolHeader,llmlogToolField,llmlogToolOutput,llmlogToolOutputLine
syn match llmlogToolHeader /^{{{ Tool: .\+$/ contained contains=llmlogToolHeaderName
syn match llmlogToolHeaderName /Tool: \zs.\+/ contained

" Tool block content
syn match llmlogToolField /^│ \w\+:/ contained contains=llmlogToolFieldName
syn match llmlogToolFieldName /│ \zs\w\+\ze:/ contained
syn match llmlogToolOutput /^│ Output:$/ contained
syn match llmlogToolOutputLine /^│   .\+$/ contained

" Box drawing characters (dimmed)
syn match llmlogBoxChar /[│┌└─┐┘┬┴┼]/

" Highlighting - llmlog specific elements
hi def link llmlogSeparator NonText
hi def link llmlogUserRole String
hi def link llmlogUserHeader None
hi def link llmlogAssistantRole Function
hi def link llmlogAssistantHeader None
hi def link llmlogTimestamp Comment

hi def link llmlogToolSummary Special
hi def link llmlogToolName Type
hi def link llmlogToolHeader Statement
hi def link llmlogToolHeaderName Type
hi def link llmlogToolField Comment
hi def link llmlogToolFieldName Identifier
hi def link llmlogToolOutput Statement
hi def link llmlogToolOutputLine Comment

hi def link llmlogBoxChar NonText

let b:current_syntax = "llmlog"
