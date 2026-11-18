" Vim syntax file
" Language:     HolyC
" Compiler:     hcc (holyc-lang.com) v0.0.15-beta
" Maintainer:   generated into this config -- see lua/engine/core/holyc.lua
"
" The keyword set below was verified against `hcc -tokens` (which labels every
" token TK_KEYWORD / TK_IDENT), so it reflects what this compiler actually
" accepts rather than TempleOS HolyC. Notably absent, and deliberately so:
" struct, enum, typedef, const, import, lastclass, no_warn, interrupt, start,
" end -- hcc lexes all of those as plain identifiers.
"
" The stdlib function / class / constant lists were harvested from the
" `hcc -lsp` completion table, so they track the installed compiler's
" /usr/local/include/tos.HH exactly.

if exists("b:current_syntax")
  finish
endif

let s:cpo_save = &cpo
set cpo&vim

syn case match

" ---------------------------------------------------------------- comments
syn keyword holycTodo contained TODO FIXME XXX NOTE HACK BUG
syn match   holycCommentAnnotation contained display "@\w\+"
syn region  holycCommentLine start="//" skip="\\$" end="$"
      \ keepend contains=holycTodo,holycCommentAnnotation,@Spell
syn region  holycComment     start="/\*" end="\*/"
      \ extend fold contains=holycTodo,holycCommentAnnotation,@Spell

" ---------------------------------------------------------------- literals
syn match  holycEscape  contained display "\\\%(x\x\+\|\o\{1,3}\|[abefnrtv\\'\"?0]\|$\)"
syn match  holycBadEscape contained display "\\[^abefnrtv\\'\"?0xX0-7$]"
" printf-style conversions -- hcc's Print/StrPrint family follows C's syntax.
syn match  holycFormat  contained display
      \ "%%\|%[-+ #0]*\%(\*\|\d\+\)\=\%(\.\%(\*\|\d\+\)\=\)\=\%(hh\|h\|ll\|l\|L\|q\|j\|z\|t\)\=[diouxXeEfFgGaAcspn]"
syn region holycString  start=+"+ skip=+\\.+ end=+"+ end=+$+
      \ extend contains=holycEscape,holycBadEscape,holycFormat,@Spell
" HolyC allows multi-character constants ('ABCD' packs into an I64).
syn match  holycCharacter "'\%(\\.\|[^\\']\)\+'" contains=holycEscape,holycBadEscape

" Decimal and hex only. hcc has no binary literal (`0b1010` silently lexes as
" 0) and no octal (`012` is twelve), so neither gets a rule here.
syn match  holycNumber  display "\<\d\+\>"
syn match  holycNumber  display "\<0[xX]\x\+\>"
syn match  holycFloat   display "\<\d\+\.\d*\%([eE][-+]\=\d\+\)\=\>"
syn match  holycFloat   display "\<\d\+[eE][-+]\=\d\+\>"
syn match  holycFloat   display "\.\d\+\%([eE][-+]\=\d\+\)\=\>"

" ------------------------------------------------------------ preprocessor
syn match  holycIncluded contained display "\"[^"]*\""
syn match  holycIncluded contained display "<[^>]*>"
syn region holycInclude  start="^\s*#\s*\%(include\|link\)\>" skip="\\$" end="$"
      \ keepend contains=holycIncluded,holycComment,holycCommentLine
syn region holycDefine   start="^\s*#\s*\%(define\|undef\)\>" skip="\\$" end="$"
      \ keepend
      \ contains=holycComment,holycCommentLine,holycString,holycCharacter,holycNumber,holycFloat,holycType,holycStdConstant
syn region holycPreCondit start="^\s*#\s*\%(ifndef\|ifdef\|ifaot\|ifjit\|elifdef\|elif\|if\)\>"
      \ skip="\\$" end="$"
      \ keepend
      \ contains=holycComment,holycCommentLine,holycNumber,holycStdConstant,holycOperator,holycDefined
syn match  holycPreCondit display "^\s*#\s*\%(else\|endif\)\>"
syn region holycPreProc  start="^\s*#\s*\%(error\|assert\|help_index\|help_file\)\>"
      \ skip="\\$" end="$"
      \ keepend contains=holycString,holycComment,holycCommentLine
" hcc rejects these outright: "invalid preprocessor directive".
syn match  holycPreProcBad display "^\s*#\s*\%(pragma\|exe\|line\|warning\|import\)\>"

" ---------------------------------------------------------------- keywords
syn keyword holycType U0 I8 U8 I16 U16 I32 U32 I64 U64 F32 F64 Bool
syn keyword holycStorageClass auto static extern _extern inline volatile
syn keyword holycStorageClass public private reg noreg atomic
syn keyword holycStructure class union nextgroup=holycTypedef skipwhite
syn keyword holycConditional if else switch case default
syn keyword holycRepeat while for do
syn keyword holycStatement break continue goto return
syn keyword holycException try catch throw
syn keyword holycOperatorKeyword sizeof alignof typeof
syn keyword holycDefined defined

" ------------------------------------------------------- names & operators
" The tag after `class`/`union` is the declared type name; reached via the
" nextgroup on those keywords.
syn match holycTypedef contained display "\h\w*"
" Any identifier applied to an argument list. `syn keyword` outranks
" `syn match`, so `if (`, `while (` and `sizeof (` stay control flow.
syn match holycFunction display "\<\h\w*\>\ze\s*("
" goto targets, anchored to line start so `? :` and `case X:` are untouched.
syn match holycLabel    display "^\s*\zs\h\w*\ze\s*:[^:=]"

" A bare `/` must not outrank the comment regions: Vim gives priority to the
" item defined last, and these come after them.
syn match holycOperator display "[-+*%<>!~^&|=?:]"
syn match holycOperator display "/\%([/*]\)\@!"
syn match holycOperator display "->"
syn match holycDelimiter display "[;,]"

" ------------------------------------------------------------------- asm
" hcc accepts `asm { ... }` (it compiles the body as a naked function, so it
" warns if you omit RET). `asm` is deliberately absent from the keyword lists
" above: a `syn keyword` outranks a region and would stop this ever starting,
" so the matchgroup highlights the `asm {` opener instead.
"
" @@N is hcc's only label form in here -- `foo:` and `foo::` are both syntax
" errors, so upstream's `\w\+::` asm-label rule is not carried over.
syn region holycAsm matchgroup=holycAsmKeyword start="\<asm\>\s*{" end="}"
      \ contains=holycAsmLabel,holycComment,holycCommentLine,holycNumber,holycString,holycCharacter
syn match  holycAsmLabel contained display "@@\d\+"

" -------------------------------------------------------- stdlib (tos.HH)
syn keyword holycStdClass CDate CDateStruct CatchFrame CsvParser CsvSlice
syn keyword holycStdClass Dirent FloatVec Fstat FzFPosition HCFs IntMap
syn keyword holycStdClass IntMapNode IntSet IntSetEntry IntSetIter IntVec
syn keyword holycStdClass Json JsonState List PtrVec RBIter RBNode RBTree
syn keyword holycStdClass StrMap StrMapNode ThreadPool ThreadSemaphore
syn keyword holycStdClass ThreadWorker ThreadWorkerJob addrinfo cDIR cStat
syn keyword holycStdClass cTimespec hostent in6_addr in_addr iovec msghdr
syn keyword holycStdClass netent protoent pthread_attr_t pthread_cond_t
syn keyword holycStdClass pthread_condattr_t pthread_handler_rec
syn keyword holycStdClass pthread_mutex_t pthread_mutexattr_t pthread_t
syn keyword holycStdClass servent sockaddr sockaddr_in sockaddr_in6
syn keyword holycStdClass sockaddr_storage sockaddr_un timeval tm

syn keyword holycStdFunction Abs Atoi CAlloc CatLenPrint CatPrint Cd
syn keyword holycStdFunction CsvParse CsvParserInit Date2Struct DayOfWeek
syn keyword holycStdFunction Dir Exit FileExtDot FileExtRem FileRead
syn keyword holycStdFunction FileWrite FirstDayOfMon FirstDayOfYear
syn keyword holycStdFunction FloatVecCapacity FloatVecClear FloatVecGet
syn keyword holycStdFunction FloatVecNew FloatVecPop FloatVecPush
syn keyword holycStdFunction FloatVecRelease FloatVecSort Free FzF
syn keyword holycStdFunction FzFPositionRelease Gcd HCC_PushFrame
syn keyword holycStdFunction HCC_Throw HCC_TryLeave I64ToStr IntMapGet
syn keyword holycStdFunction IntMapHas IntMapIter IntMapKeyIter
syn keyword holycStdFunction IntMapKeysToString IntMapNew IntMapRelease
syn keyword holycStdFunction IntMapResize IntMapSet IntMapSetFreeValue
syn keyword holycStdFunction IntMapToString IntMapValueIter IntSetAdd
syn keyword holycStdFunction IntSetDelete IntSetDiff IntSetEq IntSetHas
syn keyword holycStdFunction IntSetIterNew IntSetIterNext
syn keyword holycStdFunction IntSetIterRelease IntSetNew IntSetRelease
syn keyword holycStdFunction IntSetSize IntSetSymDiff IntSetToString
syn keyword holycStdFunction IntSetToVec IntSetUnion IntVecCapacity
syn keyword holycStdFunction IntVecClear IntVecGet IntVecNew IntVecPop
syn keyword holycStdFunction IntVecPush IntVecRelease IntVecSort IsDotC
syn keyword holycStdFunction IsDotZ IsSpace IsoFromTimespec
syn keyword holycStdFunction JsonGetStrerror JsonIsArray JsonIsBool
syn keyword holycStdFunction JsonIsFloat JsonIsInt JsonIsNull JsonIsObject
syn keyword holycStdFunction JsonIsString JsonOk JsonParse JsonPrintError
syn keyword holycStdFunction JsonRelease JsonSelect JsonToString
syn keyword holycStdFunction LastDayOfMon LastDayOfYear ListAppend
syn keyword holycStdFunction ListCount ListDeque ListEmpty ListInit
syn keyword holycStdFunction ListInsertBefore ListInsertValueBefore
syn keyword holycStdFunction ListMergeAppend ListMergePrepend ListNew
syn keyword holycStdFunction ListPop ListPrepend ListRelease MAlloc
syn keyword holycStdFunction MPrintDate MPrintQ MPrintTime
syn keyword holycStdFunction MPrintTimestampNow MSize MStrPrint Main
syn keyword holycStdFunction MemCpy MemSet MkDir ModU64 NetAccept
syn keyword holycStdFunction NetConnect NetCreateServer
syn keyword holycStdFunction NetCreateUnixClientSocket
syn keyword holycStdFunction NetCreateUnixServerSocket NetGetIpv4Address
syn keyword holycStdFunction NetGetIpv4AddressFromAcceptedSocket NetListen
syn keyword holycStdFunction NetSetSockReuseAddr NetSetSocketNoDelay
syn keyword holycStdFunction NetSetSocketNonBlocking Now NowDateTimeStruct
syn keyword holycStdFunction NowMilliseconds OutStr Pow PtrVecCapacity
syn keyword holycStdFunction PtrVecClear PtrVecGet PtrVecNew PtrVecPop
syn keyword holycStdFunction PtrVecPush PtrVecRelease PtrVecSort Pwd
syn keyword holycStdFunction QSortGeneric RBIterNew RBIterNext
syn keyword holycStdFunction RBIterRelease RBTreeDelete RBTreeForEach
syn keyword holycStdFunction RBTreeGet RBTreeHas RBTreeInsert RBTreeNew
syn keyword holycStdFunction RBTreeRelease ReAlloc Rm RmDir SPutChar Sh
syn keyword holycStdFunction Shlurp Stat Str2CDateStruct StrCmp StrCpy
syn keyword holycStdFunction StrFirstOcc StrFirstRem StrHash StrIntToHex
syn keyword holycStdFunction StrLastOcc StrLastRem StrLen StrMapGet
syn keyword holycStdFunction StrMapGetLen StrMapHas StrMapHasLen
syn keyword holycStdFunction StrMapIter StrMapKeyIter StrMapKeysToString
syn keyword holycStdFunction StrMapNew StrMapRelease StrMapResize
syn keyword holycStdFunction StrMapSet StrMapSetFreeKey StrMapSetFreeValue
syn keyword holycStdFunction StrMapToString StrMapValueIter StrMerge
syn keyword holycStdFunction StrMergeJoin StrNCmp StrNCpy StrNICmp StrNew
syn keyword holycStdFunction StrOcc StrPrint StrPrintJoin StrReverse
syn keyword holycStdFunction StrToCDate StrTrimEnd StrTrimStart
syn keyword holycStdFunction Struct2Date System ThreadPoolEnqueue
syn keyword holycStdFunction ThreadPoolNew ThreadPoolRelease
syn keyword holycStdFunction ThreadPoolStop ThreadPoolWait ToLower ToUpper
syn keyword holycStdFunction U64ToStr WildMatch Write YearStartDate accept
syn keyword holycStdFunction acos acosh asin asinh atan atan2 atanh bind
syn keyword holycStdFunction cbrt ceil chdir close closedir connect
syn keyword holycStdFunction copysign cos cosh creat endhostent endnetent
syn keyword holycStdFunction endprotoent endservent erf erfc exp exp2
syn keyword holycStdFunction expm1 fabs fcntl fdim floor fma fmax fmin
syn keyword holycStdFunction fmod fork free freeaddrinfo frexp fstat
syn keyword holycStdFunction gai_strerror getaddrinfo gethostbyaddr
syn keyword holycStdFunction gethostbyname gethostent getnameinfo
syn keyword holycStdFunction getnetbyaddr getnetbyname getnetent
syn keyword holycStdFunction getpeername getprotobyname getprotobynumber
syn keyword holycStdFunction getprotoent getservbyname getservbyport
syn keyword holycStdFunction getservent getsockname getsockopt
syn keyword holycStdFunction gettimeofday hstrerror hypot ilogb inet_addr
syn keyword holycStdFunction inet_aton inet_lnaof inet_makeaddr inet_netof
syn keyword holycStdFunction inet_network inet_ntoa inet_ntop inet_pton
syn keyword holycStdFunction ldexp lgamma listen localtime log log10 log1p
syn keyword holycStdFunction log2 logb longjmp lrint lround lseek lstat
syn keyword holycStdFunction malloc memchr memcmp memmove mkdir modf nan
syn keyword holycStdFunction nearbyint nextafter open opendir pow printf
syn keyword holycStdFunction pthread_attr_init pthread_attr_setstacksize
syn keyword holycStdFunction pthread_cond_broadcast pthread_cond_destroy
syn keyword holycStdFunction pthread_cond_init pthread_cond_signal
syn keyword holycStdFunction pthread_cond_wait pthread_create
syn keyword holycStdFunction pthread_detach pthread_exit pthread_join
syn keyword holycStdFunction pthread_mutex_destroy pthread_mutex_init
syn keyword holycStdFunction pthread_mutex_lock pthread_mutex_unlock read
syn keyword holycStdFunction readdir recv recvfrom recvmsg remainder
syn keyword holycStdFunction remquo rewinddir rint rmdir round scalbln
syn keyword holycStdFunction scalbn seekdir send sendmsg sendto sethostent
syn keyword holycStdFunction setjmp setnetent setprotoent setservent
syn keyword holycStdFunction setsockopt shutdown sin sinh snprintf socket
syn keyword holycStdFunction sqrt stat strcasecmp strcat strchr strcmp
syn keyword holycStdFunction strcoll strcpy strcspn strdup strerror strlen
syn keyword holycStdFunction strncat strncmp strncpy strnlen strpbrk
syn keyword holycStdFunction strrchr strspn strstr strtod strtok strtoll
syn keyword holycStdFunction strtoul strxfrm tan tanh telldir tgamma trunc
syn keyword holycStdFunction unlink wait waitpid write

syn keyword holycStdConstant AF_INET AF_INET6 AF_UNIX AF_UNSPEC
syn keyword holycStdConstant AI_CANONNAME AI_NUMERICHOST AI_NUMERICSERV
syn keyword holycStdConstant AI_PASSIVE AI_UNUSABLE CDATE_BASE_DAY_OF_WEEK
syn keyword holycStdConstant CDATE_YEAR_DAYS CDATE_YEAR_DAYS_INT
syn keyword holycStdConstant CH_BACKSPACE CH_ESC CH_SHIFT_ESC
syn keyword holycStdConstant CH_SHIFT_SPACE CH_SPACE CSV_EOF CSV_FIELD
syn keyword holycStdConstant CSV_ROW DIR_MAXPATHLEN DT_BLK DT_CHR DT_DIR
syn keyword holycStdConstant DT_FIFO DT_LNK DT_REG DT_SOCK DT_UNKNOWN
syn keyword holycStdConstant DT_WHT EXIT_FAIL EXIT_OK FALSE FD_CLOEXEC
syn keyword holycStdConstant FZF_CASE_IGNORE FZF_CASE_RESPECT
syn keyword holycStdConstant FZF_CASE_SMART F_CHKCLEAN F_DUPFD
syn keyword holycStdConstant F_FLUSH_DATA F_GETFD F_GETFL F_GETLK F_GETOWN
syn keyword holycStdConstant F_PREALLOCATE F_RDADVISE F_RDAHEAD F_RDLCK
syn keyword holycStdConstant F_SETFD F_SETFL F_SETLK F_SETLKW F_SETOWN
syn keyword holycStdConstant F_SETSIZE F_UNLCK F_WRLCK HT_DELETED HT_LOAD
syn keyword holycStdConstant HT_PROBE_1 HT_PROBE_3 I64_MAX I64_MIN I8_MAX
syn keyword holycStdConstant I8_MIN INET6_ADDRSTRLEN IPPROTO_IP
syn keyword holycStdConstant IPPROTO_IPV6 IS_MACOS IS_X86_64 JSON_ARRAY
syn keyword holycStdConstant JSON_BOOL JSON_CANNOT_ADVANCE
syn keyword holycStdConstant JSON_CANNOT_START_PARSE JSON_EOF JSON_FLOAT
syn keyword holycStdConstant JSON_INT JSON_INVALID_ARRAY_CHARACTER
syn keyword holycStdConstant JSON_INVALID_BOOL JSON_INVALID_DECIMAL
syn keyword holycStdConstant JSON_INVALID_ESCAPE_CHARACTER
syn keyword holycStdConstant JSON_INVALID_HEX JSON_INVALID_JSON_TYPE_CHAR
syn keyword holycStdConstant JSON_INVALID_KEY_TERMINATOR_CHARACTER
syn keyword holycStdConstant JSON_INVALID_KEY_VALUE_SEPARATOR
syn keyword holycStdConstant JSON_INVALID_NUMBER JSON_INVALID_SIGN
syn keyword holycStdConstant JSON_INVALID_STRING_NOT_TERMINATED
syn keyword holycStdConstant JSON_INVALID_TYPE JSON_INVALID_UTF16
syn keyword holycStdConstant JSON_INVALID_UTF16_SURROGATE JSON_NULL
syn keyword holycStdConstant JSON_OBJECT JSON_OK JSON_STRING JSON_STRNUM
syn keyword holycStdConstant JSON_STRNUM_FLAG MKDIR_DEFAULT NULL O_ACCMODE
syn keyword holycStdConstant O_APPEND O_CREAT O_EXCL O_NONBLOCK O_RDONLY
syn keyword holycStdConstant O_RDWR O_TRUNC O_WRONLY PERSIST_TIMEOUT
syn keyword holycStdConstant PRTF_AUX_FMT_NUM PRTF_COMMA PRTF_DECIMAL
syn keyword holycStdConstant PRTF_DOLLAR PRTF_LEFT_JUSTIFY PRTF_NEG
syn keyword holycStdConstant PRTF_NEG_AUX_FMT_NUM PRTF_NEG_E PRTF_PAD_ZERO
syn keyword holycStdConstant PRTF_QUESTION PRTF_SLASH PRTF_TRUNCATE
syn keyword holycStdConstant RM_FORCE RM_RECURSE RM_VERBOSE SEEK_CUR
syn keyword holycStdConstant SEEK_END SEEK_SET SF_ARG1 SF_ARG2 SF_ARG3
syn keyword holycStdConstant SF_ARG4 SF_ARG5 SF_ARG6 SF_ARG7 SF_ARG8
syn keyword holycStdConstant SOCK_DGRAM SOCK_RAW SOCK_SEQPACKET
syn keyword holycStdConstant SOCK_STREAM SOL_SOCKET SO_ACCEPTCONN
syn keyword holycStdConstant SO_BROADCAST SO_DEBUG SO_DONTROUTE
syn keyword holycStdConstant SO_KEEPALIVE SO_LINGER SO_OOBINLINE
syn keyword holycStdConstant SO_REUSEADDR SO_REUSEPORT SO_TIMESTAMP
syn keyword holycStdConstant SO_TIMESTAMP_MONOTONIC STDERR STDIN STDOUT
syn keyword holycStdConstant STR_LEN S_IFBLK S_IFCHR S_IFDIR S_IFIFO
syn keyword holycStdConstant S_IFLNK S_IFMT S_IFREG S_IFSOCK S_IRGRP
syn keyword holycStdConstant S_IROTH S_IRUSR S_IRWXG S_IRWXO S_IRWXU
syn keyword holycStdConstant S_ISGID S_ISUID S_ISVTX S_IWGRP S_IWOTH
syn keyword holycStdConstant S_IWUSR S_IXGRP S_IXOTH S_IXUSR
syn keyword holycStdConstant TCP_CONNECTIONTIMEOUT TCP_CONNECTION_INFO
syn keyword holycStdConstant TCP_ENABLE_ECN TCP_FASTOPEN TCP_KEEPALIVE
syn keyword holycStdConstant TCP_KEEPCNT TCP_KEEPINTVL TCP_MAXSEG
syn keyword holycStdConstant TCP_NODELAY TCP_NOOPT TCP_NOPUSH
syn keyword holycStdConstant TCP_RXT_CONNDROPTIME TCP_RXT_FINDROP
syn keyword holycStdConstant TCP_SENDMOREACKS TRUE U64_MAX U8_MAX
syn keyword holycStdConstant _SS_PAD1SIZE _SS_PAD2SIZE __ARCH__ __BUFSIZ__
syn keyword holycStdConstant __DATE__ __HCC_AOT__ __HCC_VERSION__
syn keyword holycStdConstant __MUTEX_LOCK_ATTR_SIZE__
syn keyword holycStdConstant __MUTEX_LOCK_PADDING__ __THREAD_ATTR_SIZE__
syn keyword holycStdConstant __THREAD_CONDATTR_SIZE__ __THREAD_COND_SIZE__
syn keyword holycStdConstant __THREAD_SIZE__ __TIMESTAMP__ __TIME__
syn keyword holycStdConstant __macos__ __aarch64__ __arm64__ __x86_64__

syn keyword holycStdVariable Fs argc argv

" Types declared in this buffer. The keyword list is (re)built by
" engine.core.holyc on write and on leaving insert mode -- a syntax file has
" no view of the file's own declarations, and hcc's server offers no semantic
" tokens to do this properly. Scoped to the current buffer only.

" ------------------------------------------------------------------- sync
syn sync ccomment holycComment minlines=50

" -------------------------------------------------------------- highlight
hi def link holycTodo           Todo
hi def link holycCommentLine    Comment
hi def link holycComment        Comment

hi def link holycString         String
hi def link holycCharacter      Character
hi def link holycEscape         SpecialChar
hi def link holycBadEscape      Error
hi def link holycFormat         SpecialChar
hi def link holycNumber         Number
hi def link holycFloat          Float

hi def link holycInclude        Include
hi def link holycIncluded       String
hi def link holycDefine         Define
hi def link holycPreCondit      PreCondit
hi def link holycPreProc        PreProc
hi def link holycPreProcBad     Error

hi def link holycType           Type
hi def link holycStorageClass   StorageClass
hi def link holycStructure      Structure
hi def link holycConditional    Conditional
hi def link holycRepeat         Repeat
hi def link holycStatement      Statement
hi def link holycException      Exception
hi def link holycOperatorKeyword Operator
hi def link holycDefined        PreCondit

hi def link holycTypedef        Typedef
hi def link holycFunction       Function
hi def link holycLabel          Label
hi def link holycOperator       Operator
hi def link holycDelimiter      Delimiter

hi def link holycStdClass       Type
hi def link holycStdFunction    Function
hi def link holycStdConstant    Constant
hi def link holycStdVariable    Identifier
hi def link holycUserType       Type

hi def link holycCommentAnnotation SpecialComment
hi def link holycAsmKeyword     Keyword
hi def link holycAsmLabel       Label

let b:current_syntax = "holyc"

let &cpo = s:cpo_save
unlet s:cpo_save
