* mv - move file
*
* Itagaki Fumihiko 30-Aug-92  Create.
* 1.2
* Itagaki Fumihiko 06-Nov-92  Human68kのfatchkのバグ対策．
*                             strip_excessive_slashesのバグfixに伴う改版．
*                             些細なメッセージ変更．
* 1.3
* Itagaki Fumihiko 16-Dec-92  引数が 2つ（mv a b）のとき，b が存在するディ
*                             レクトリであっても，a と b が同じエントリを
*                             指すパス名である場合には特別に mv d1 d2 の形
*                             式として処理するようにした．これでディレクト
*                             リに対しても CASE.X と同じこと（同じ綴りのま
*                             ま大文字／小文字を変更する）が可能になった．
* Itagaki Fumihiko 27-Dec-92  -I オプションの追加．
* Itagaki Fumihiko 27-Dec-92  -m オプションの追加．
* 1.4
* Itagaki Fumihiko 10-Jan-93  GETPDB -> lea $10(a0),a0
* Itagaki Fumihiko 12-Jan-93  -e オプションの追加．
* Itagaki Fumihiko 20-Jan-93  引数 - と -- の扱いの変更
* Itagaki Fumihiko 22-Jan-93  スタックを拡張
* Itagaki Fumihiko 24-Jan-93  v1.4 での identical check が正常に行われない
*                             エンバグを修正
* Itagaki Fumihiko 25-Jan-93  エラー・メッセージの修正
* 1.5
*
* Usage: mv [ -Ifiuvx ] [ -m {[ugoa]{{+-=}[ashrwx]}...}[,...] ] [ -- ] <ファイル1> <ファイル2>
*        mv [ -Ifiuvx ] [ -m {[ugoa]{{+-=}[ashrwx]}...}[,...] ] [ -- ] <ディレクトリ1> <ディレクトリ2>
*        mv [ -Iefiuvx ] [ -m {[ugoa]{{+-=}[ashrwx]}...}[,...] ] [ -- ] <ファイル> ... <ディレクトリ>

.include doscall.h
.include error.h
.include limits.h
.include stat.h
.include chrcode.h

.xref DecodeHUPAIR
.xref getlnenv
.xref issjis
.xref strlen
.xref strcpy
.xref strfor1
.xref headtail
.xref cat_pathname
.xref strip_excessive_slashes
.xref fclose

REQUIRED_OSVER	equ	$200			*  2.00以降

STACKSIZE	equ	16384			*  スーパーバイザモードでは15KB以上必要
GETSLEN		equ	32

FLAG_f		equ	0
FLAG_i		equ	1
FLAG_I		equ	2
FLAG_u		equ	3
FLAG_v		equ	4
FLAG_x		equ	5
FLAG_e		equ	6

LNDRV_O_CREATE		equ	4*2
LNDRV_O_OPEN		equ	4*3
LNDRV_O_DELETE		equ	4*4
LNDRV_O_MKDIR		equ	4*5
LNDRV_O_RMDIR		equ	4*6
LNDRV_O_CHDIR		equ	4*7
LNDRV_O_CHMOD		equ	4*8
LNDRV_O_FILES		equ	4*9
LNDRV_O_RENAME		equ	4*10
LNDRV_O_NEWFILE		equ	4*11
LNDRV_O_FATCHK		equ	4*12
LNDRV_realpathcpy	equ	4*16
LNDRV_LINK_FILES	equ	4*17
LNDRV_OLD_LINK_FILES	equ	4*18
LNDRV_link_nest_max	equ	4*19
LNDRV_getrealpath	equ	4*20

.text
start:
		bra.s	start1
		dc.b	'#HUPAIR',0
start1:
		lea	stack_bottom(pc),a7		*  A7 := スタックの底
		DOS	_VERNUM
		cmp.w	#REQUIRED_OSVER,d0
		bcs	dos_version_mismatch

		lea	$10(a0),a0			*  A0 : PDBアドレス
		move.l	a7,d0
		sub.l	a0,d0
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_SETBLOCK
		addq.l	#8,a7
	*
	*  引数並び格納エリアを確保する
	*
		lea	1(a2),a0			*  A0 := コマンドラインの文字列の先頭アドレス
		bsr	strlen				*  D0.L := コマンドラインの文字列の長さ
		addq.l	#1,d0
		bsr	malloc
		bmi	insufficient_memory

		movea.l	d0,a1				*  A1 := 引数並び格納エリアの先頭アドレス
	*
	*  バッファを確保する
	*
		move.l	#$00ffffff,d0
		bsr	malloc
		sub.l	#$81000000,d0
		cmp.l	#1024,d0
		blo	insufficient_memory

		move.l	d0,d4				*  D4.L : バッファサイズ
		bsr	malloc
		bmi	insufficient_memory

		movea.l	d0,a4				*  A4 : バッファ
	*
	*  lndrv が組み込まれているかどうかを検査する
	*
		bsr	getlnenv
		move.l	d0,lndrv
	*
	*  引数をデコードし，解釈する
	*
		bsr	DecodeHUPAIR			*  引数をデコードする
		movea.l	a1,a0				*  A0 : 引数ポインタ
		move.l	d0,d7				*  D7.L : 引数カウンタ
		move.b	#$ff,mode_mask
		clr.b	mode_plus
		moveq	#0,d5				*  D5.L : flags
decode_opt_loop1:
		tst.l	d7
		beq	decode_opt_done

		cmpi.b	#'-',(a0)
		bne	decode_opt_done

		tst.b	1(a0)
		beq	decode_opt_done

		subq.l	#1,d7
		addq.l	#1,a0
		move.b	(a0)+,d0
		cmp.b	#'-',d0
		bne	decode_opt_loop2

		tst.b	(a0)+
		beq	decode_opt_done

		subq.l	#1,a0
decode_opt_loop2:
		cmp.b	#'f',d0
		beq	set_option_f

		cmp.b	#'i',d0
		beq	set_option_i

		cmp.b	#'I',d0
		beq	set_option_I

		moveq	#FLAG_u,d1
		cmp.b	#'u',d0
		beq	set_option

		moveq	#FLAG_v,d1
		cmp.b	#'v',d0
		beq	set_option

		moveq	#FLAG_x,d1
		cmp.b	#'x',d0
		beq	set_option

		moveq	#FLAG_e,d1
		cmp.b	#'e',d0
		beq	set_option

		cmp.b	#'m',d0
		beq	decode_mode

		moveq	#1,d1
		tst.b	(a0)
		beq	bad_option_1

		bsr	issjis
		bne	bad_option_1

		moveq	#2,d1
bad_option_1:
		move.l	d1,-(a7)
		pea	-1(a0)
		move.w	#2,-(a7)
		lea	msg_illegal_option(pc),a0
		bsr	werror_myname_and_msg
		DOS	_WRITE
		lea	10(a7),a7
		bra	usage

set_option_I:
		bset	#FLAG_I,d5
set_option_i:
		bset	#FLAG_i,d5
		bclr	#FLAG_f,d5
		bra	set_option_done

set_option_f:
		bset	#FLAG_f,d5
		bclr	#FLAG_i,d5
		bclr	#FLAG_I,d5
		bra	set_option_done

set_option:
		bset	d1,d5
set_option_done:
		move.b	(a0)+,d0
		bne	decode_opt_loop2
		bra	decode_opt_loop1

decode_mode:
		tst.b	(a0)+
		bne	bad_arg

		subq.l	#1,d7
		bcs	too_few_args

		move.b	#$ff,mode_mask
		clr.b	mode_plus
decode_mode_loop1:
		move.b	(a0)+,d0
		beq	decode_opt_loop1

		cmp.b	#',',d0
		beq	decode_mode_loop1

		subq.l	#1,a0
decode_mode_loop2:
		move.b	(a0)+,d0
		cmp.b	#'u',d0
		beq	decode_mode_loop2

		cmp.b	#'g',d0
		beq	decode_mode_loop2

		cmp.b	#'o',d0
		beq	decode_mode_loop2

		cmp.b	#'a',d0
		beq	decode_mode_loop2
decode_mode_loop3:
		cmp.b	#'+',d0
		beq	decode_mode_plus

		cmp.b	#'-',d0
		beq	decode_mode_minus

		cmp.b	#'=',d0
		bne	bad_arg

		move.b	#(MODEVAL_VOL|MODEVAL_DIR|MODEVAL_LNK),mode_mask
		clr.b	mode_plus
decode_mode_plus:
		bsr	decode_mode_sub
		or.b	d1,mode_plus
		bra	decode_mode_continue

decode_mode_minus:
		bsr	decode_mode_sub
		not.b	d1
		and.b	d1,mode_mask
		and.b	d1,mode_plus
decode_mode_continue:
		tst.b	d0
		beq	decode_opt_loop1

		cmp.b	#',',d0
		beq	decode_mode_loop1
		bra	decode_mode_loop3

decode_mode_sub:
		moveq	#0,d1
decode_mode_sub_loop:
		move.b	(a0)+,d0
		moveq	#MODEBIT_ARC,d2
		cmp.b	#'a',d0
		beq	decode_mode_sub_set

		moveq	#MODEBIT_SYS,d2
		cmp.b	#'s',d0
		beq	decode_mode_sub_set

		moveq	#MODEBIT_HID,d2
		cmp.b	#'h',d0
		beq	decode_mode_sub_set

		cmp.b	#'r',d0
		beq	decode_mode_sub_loop

		moveq	#MODEBIT_RDO,d2
		cmp.b	#'w',d0
		beq	decode_mode_sub_set

		moveq	#MODEBIT_EXE,d2
		cmp.b	#'x',d0
		beq	decode_mode_sub_set

		rts

decode_mode_sub_set:
		bset	d2,d1
		bra	decode_mode_sub_loop

decode_opt_done:
		subq.l	#2,d7
		bcs	too_few_args
	*
	*  標準入力が端末であるかどうかを調べておく
	*
		moveq	#0,d0				*  標準入力は
		bsr	is_chrdev			*  キャラクタデバイス
		sne	stdin_is_terminal
	*
	*  処理開始
	*
		moveq	#0,d6				*  D6.W : エラー・コード
	*
	*  引数は 2個以上 -> targetを調べる
	*
		movea.l	a0,a1				*  A1 : 1st source
		move.l	d7,d0
find_target:
		bsr	strfor1
		subq.l	#1,d0
		bcc	find_target
							*  A0 : target
		bsr	strip_excessive_slashes
		bsr	is_directory
		exg	a0,a1				*  A0 : 1st source, A1 : target
		bmi	exit_program
		bne	mv_into_dir

		*  target はディレクトリではない

		tst.l	d7
		beq	mv_source_to_target

		movea.l	a1,a0
		bsr	lgetmode
		lea	msg_not_a_directory(pc),a2
		bpl	mv_error_exit

		lea	msg_nodir(pc),a2
mv_error_exit:
		bsr	werror_myname_word_colon_msg
		bra	exit_program

mv_source_to_target:
		bsr	strip_excessive_slashes
		bsr	move_file
		bra	exit_program

mv_into_dir:
		tst.l	d7
		bne	mv_into_dir_loop

		bsr	is_identical
		beq	mv_source_to_target
mv_into_dir_loop:
		movea.l	a0,a2
		bsr	strfor1
		exg	a0,a2				*  A2 : next arg
		bsr	strip_excessive_slashes
		bsr	move_into_dir
		movea.l	a2,a0
		subq.l	#1,d7
		bcc	mv_into_dir_loop
exit_program:
		move.w	d6,-(a7)
		DOS	_EXIT2

bad_arg:
		lea	msg_bad_arg(pc),a0
		bra	arg_error

too_few_args:
		lea	msg_too_few_args(pc),a0
arg_error:
		bsr	werror_myname_and_msg
usage:
		lea	msg_usage(pc),a0
		bsr	werror
		moveq	#1,d6
		bra	exit_program

dos_version_mismatch:
		lea	msg_dos_version_mismatch(pc),a0
		bra	mv_error_exit_3

insufficient_memory:
		lea	msg_no_memory(pc),a0
mv_error_exit_3:
		bsr	werror_myname_and_msg
		moveq	#3,d6
		bra	exit_program
*****************************************************************
* move_into_dir
*
*      A0 で示されるエントリを A1 で示されるディレクトリ下に移動する
*
* RETURN
*      none
*****************************************************************
move_into_dir:
		movem.l	d0-d3/a0-a3,-(a7)
		movea.l	a1,a2
		bsr	headtail
		exg	a1,a2				*  A2 : tail of source
		move.l	a0,-(a7)
		lea	new_pathname(pc),a0
		bsr	cat_pathname_x
		movea.l	(a7)+,a1
		bmi	move_into_dir_done

		exg	a0,a1
		bsr	move_file
move_into_dir_done:
		movem.l	(a7)+,d0-d3/a0-a3
		rts
*****************************************************************
* move_file - ファイルを移動する
*
* CALL
*      A0     source path
*      A1     target path
*
* RETURN
*      D0-D3/A0-A3  破壊
*****************************************************************
move_file:
		*  source を調べる
		bsr	lgetmode
		bmi	perror

		move.l	d0,d1				*  D1.L : source の mode

		*  target を調べる
		exg	a0,a1				*  A0:target, A1:source
		bsr	lgetmode
		move.l	d0,d2				*  D2.L : target の mode
		bpl	move_file_target_exists

		cmp.l	#ENOFILE,d0
		beq	move_file_new

		cmp.l	#ENODIR,d0
		bne	perror

		bsr	headtail
		clr.b	(a1)
		bsr	strip_excessive_slashes
		lea	msg_nodir(pc),a2
		bra	werror_myname_word_colon_msg

move_file_target_exists:
		bsr	is_identical			*  src と dest が同一なら
		beq	move_file_new			*  rename(src,dest) してかまわない

		lea	msg_directory_exists(pc),a2
		btst	#MODEBIT_DIR,d2			*  targetがディレクトリだと
		bne	move_error			*  上書きできないのでエラー

		btst	#MODEBIT_DIR,d1
		bne	update_ok

		btst	#FLAG_u,d5
		beq	update_ok

		bsr	lgetdate
		bcc	update_ok

		move.l	d0,d3				*  D3.L : target のタイム・スタンプ
		exg	a0,a1
		bsr	lgetdate			*  D0.L : source のタイム・スタンプ
		exg	a0,a1
		bcc	update_ok

		cmp.l	d3,d0
		bls	move_file_return
update_ok:
		bsr	confirm_replace
		bne	move_file_return

		*  target を削除する
		bsr	unlink
			* エラー処理省略
		bra	move_file_new_ok

move_file_new:
		btst	#FLAG_I,d5
		beq	move_file_new_ok

		bsr	confirm_move
		bne	move_file_return
move_file_new_ok:
		btst	#FLAG_v,d5
		beq	verbose_done

		move.l	a1,-(a7)
		DOS	_PRINT
		pea	msg_arrow(pc)
		DOS	_PRINT
		move.l	a0,(a7)
		DOS	_PRINT
		pea	msg_newline(pc)
		DOS	_PRINT
		lea	12(a7),a7
verbose_done:
		exg	a0,a1				*  A0:source, A1:target
		*  sourceを通常のファイルにchmodする
		moveq	#MODEVAL_ARC,d0
		bsr	lchmod
		bmi	perror

		*  sourceがディレクトリなら、ここで、targetをtargetにrenameしてみる
		*  もし ENODIR が返されるなら、ディレクトリをそのサブディレクトリに
		*  移動しようとしていることになる
		btst	#MODEBIT_DIR,d1
		beq	do_move_file

		move.l	a1,-(a7)
		move.l	a1,-(a7)
		DOS	_RENAME
		addq.l	#8,a7
		move.l	d0,d2
		cmp.l	#ENODIR,d2
		beq	simple_move_failed
do_move_file:
		*  移動する
		move.l	a1,-(a7)
		move.l	a0,-(a7)
		DOS	_RENAME
		addq.l	#8,a7
		move.l	d0,d2
		bmi	simple_move_failed

		movea.l	a1,a0
		move.l	d1,d0
		bsr	newmode
		bsr	lchmod
		bmi	perror
.if 0
		btst	#MODEBIT_DIR,d1
		beq	move_file_return

		lea	nameck_buffer(pc),a0
		move.l	a0,-(a7)
		move.l	a1,-(a7)
		DOS	_NAMECK
		addq.l	#8,a7
		tst.l	d0
		bmi	warning_mvdir

		bsr	strip_excessive_slashes
		bsr	getrealpath
		bmi	warning_mvdir

		bsr	lgetmode
		bmi	warning_mvdir

		btst	#MODEBIT_DIR,d0
		beq	warning_mvdir

		lea	target_fatchkbuf(pc),a2
		bsr	fatchk
.endif
move_file_return:
		rts

simple_move_failed:
	*
	*  エラー
	*
		move.l	d1,d0
		bsr	lchmod				*  sourceのmodeを元に戻す
		bmi	perror
	*
	*  考えられる原因 :-
	*    ディレクトリをそのサブディレクトリに移動しようとした ... ENODIR
	*    ファイルが存在する ... EMVEXISTS
	*    ディレクトリが一杯 ... EDIRFULL
	*    ドライブが異なる ... EBADDRV
	*
		exg	a0,a1				*  A0:target, A1:source
		lea	msg_cannot_move_dir_to_its_sub(pc),a2
		cmp.l	#ENODIR,d2
		beq	move_error

		lea	msg_semicolon_file_exists(pc),a2
		cmp.l	#EMVEXISTS,d2
		beq	move_error

		lea	msg_semicolon_directory_full(pc),a2
		cmp.l	#EDIRFULL,d2
		beq	move_error

		lea	msg_nul(pc),a2
		cmp.l	#EBADDRV,d2
		bne	move_error

		lea	msg_cannot_move_dirvol_across(pc),a2
		btst	#MODEBIT_VOL,d1
		bne	move_error

		btst	#MODEBIT_DIR,d1
		bne	move_error
	*
	*  ドライブが異なる
	*
		lea	msg_drive_differ(pc),a2
		btst	#FLAG_x,d5
		bne	move_error
		*
		*  source を open する
		*
		exg	a0,a1				*  A0:source, A1:target
		bsr	lopen				*  source をオープンする
		bmi	perror

		move.l	d0,d2				*  D2.L : source のファイル・ハンドル
		*
		*  target を create する
		*
		move.w	d1,d0
		bsr	newmode
		move.w	d0,-(a7)
		move.l	a1,-(a7)			*  target file を
		DOS	_CREATE				*  作成する
		addq.l	#6,a7				*  （ドライブの検査は済んでいる）
		move.l	d0,d1				*  D1.L : target のファイル・ハンドル
		bmi	copy_file_perror_2
		*
		*  ファイルの内容をコピーする
		*
copy_loop:
		move.l	d4,-(a7)
		move.l	a4,-(a7)
		move.w	d2,-(a7)
		DOS	_READ
		lea	10(a7),a7
		tst.l	d0
		bmi	copy_file_perror_3
		beq	copy_file_contents_done

		move.l	d0,d3
		move.l	d0,-(a7)
		move.l	a4,-(a7)
		move.w	d1,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		tst.l	d0
		bmi	copy_file_perror_4

		cmp.l	d3,d0
		blt	copy_file_disk_full

		bra	copy_loop

copy_file_contents_done:
		*
		*  ファイルのタイムスタンプをコピーする
		*
		move.w	d2,d0
		bsr	fgetdate
		bcc	copy_timestamp_done

		move.l	d0,-(a7)
		move.w	d1,-(a7)
		DOS	_FILEDATE
		addq.l	#6,a7
			* エラー処理省略 (無視)
copy_timestamp_done:
		move.w	d1,d0
		bsr	fclose
			* エラー処理省略
		move.w	d2,d0
		bsr	fclose
			* エラー処理省略
		*
		*  source を削除する
		*
		bra	unlink

move_error:
		exg	a0,a1
		bsr	werror_myname_and_msg
		lea	msg_wo(pc),a0
		bsr	werror
		movea.l	a1,a0
		bsr	werror
		lea	msg_cannot_move(pc),a0
		bsr	werror
		movea.l	a2,a0
		bsr	werror
		bra	werror_newline_and_set_error

copy_file_perror_2:
		movea.l	a1,a0
copy_file_perror_1:
		move.l	d0,-(a7)
		move.w	d2,d0				*  source を
		bsr	fclose				*  close する
		move.l	(a7)+,d0
		bra	perror

copy_file_disk_full:
		moveq	#EDISKFULL,d0
copy_file_perror_4:
		movea.l	a1,a0
copy_file_perror_3:
		move.l	d0,-(a7)
		move.w	d1,d0				*  target を
		bsr	fclose				*  close する
		move.l	(a7)+,d0
		bra	copy_file_perror_1
*****************************************************************
confirm_replace:
		*  標準入力が端末ならば，ボリューム・ラベル，シンボリック・リンク，
		*  読み込み専用，隠し，システムのどれかの属性ビットがONである場合，
		*  問い合わせる

		tst.b	stdin_is_terminal
		beq	confirm_i

		move.b	d2,d0
		and.b	#(MODEVAL_VOL|MODEVAL_LNK|MODEVAL_RDO|MODEVAL_HID|MODEVAL_SYS),d0
		bne	confirm
confirm_i:
		btst	#FLAG_i,d5
		beq	confirm_yes
confirm:
		btst	#FLAG_f,d5
		bne	confirm_yes

		bsr	werror_myname
		move.l	a0,-(a7)
		move.l	a1,a0
		bsr	werror
		lea	msg_destination(pc),a0
		bsr	werror
		movea.l	(a7),a0
		bsr	werror
		lea	msg_ni(pc),a0
		bsr	werror

		lea	msg_vollabel(pc),a0
		btst	#MODEBIT_VOL,d2
		bne	confirm_5

		lea	msg_symlink(pc),a0
		btst	#MODEBIT_LNK,d2
		bne	confirm_5

		btst	#MODEBIT_RDO,d2
		beq	confirm_2

		lea	msg_readonly(pc),a0
		bsr	werror
confirm_2:
		btst	#MODEBIT_HID,d2
		beq	confirm_3

		lea	msg_hidden(pc),a0
		bsr	werror
confirm_3:
		btst	#MODEBIT_SYS,d2
		beq	confirm_4

		lea	msg_system(pc),a0
		bsr	werror
confirm_4:
		lea	msg_file(pc),a0
confirm_5:
		bsr	werror
		lea	msg_confirm_replace(pc),a0
do_confirm:
		bsr	werror
		lea	getsbuf(pc),a0
		move.b	#GETSLEN,(a0)
		move.l	a0,-(a7)
		DOS	_GETS
		addq.l	#4,a7
		bsr	werror_newline
		move.b	1(a0),d0
		beq	confirm_6

		move.b	2(a0),d0
confirm_6:
		movea.l	(a7)+,a0
confirm_return:
		cmp.b	#'y',d0
		rts

confirm_yes:
		moveq	#'y',d0
		bra	confirm_return

confirm_move:
		bsr	werror_myname
		exg	a0,a1
		bsr	werror
		exg	a0,a1
		move.l	a0,-(a7)
		lea	msg_wo(pc),a0
		bsr	werror
		move.l	(a7),a0
		bsr	werror
		lea	msg_confirm_move(pc),a0
		bra	do_confirm
*****************************************************************
newmode:
		bchg	#MODEBIT_RDO,d0
		and.b	mode_mask,d0
		or.b	mode_plus,d0
		bchg	#MODEBIT_RDO,d0
		rts
*****************************************************************
malloc:
		move.l	d0,-(a7)
		DOS	_MALLOC
		addq.l	#4,a7
		tst.l	d0
		rts
*****************************************************************
unlink:
		move.w	#MODEVAL_ARC,-(a7)
		move.l	a0,-(a7)
		DOS	_CHMOD
		DOS	_DELETE
		addq.l	#6,a7
		rts
*****************************************************************
lgetmode:
		moveq	#-1,d0
lchmod:
		move.w	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_CHMOD
		addq.l	#6,a7
		tst.l	d0
		rts
*****************************************************************
fclosex:
		bpl	fclose
		rts
.if 0
*****************************************************************
* getrealpath - シンボリック・リンクの実体のパス名を得る
*
* CALL
*      A0     パス名
*
* RETURN
*      pathname_buf   (A0) がリンクなら，その実体のパス名
*                     そうでなければ (A0) がコピーされる
*
*      D0.L   エラーなら負
*      CCR    TST.L D0
*****************************************************************
getrealpath:
		movem.l	d1/a0-a2,-(a7)
		lea	pathname_buf(pc),a1
		move.l	lndrv,d0
		beq	getrealpath_thru

		movea.l	d0,a2
		movea.l	LNDRV_getrealpath(a2),a2
		clr.l	-(a7)
		DOS	_SUPER				*  スーパーバイザ・モードに切り換える
		addq.l	#4,a7
		move.l	d0,-(a7)			*  前の SSP の値
		movem.l	d2-d7/a0-a6,-(a7)
		move.l	a0,-(a7)
		move.l	a1,-(a7)
		jsr	(a2)
		addq.l	#8,a7
		movem.l	(a7)+,d2-d7/a0-a6
		move.l	d0,d1
		DOS	_SUPER				*  ユーザ・モードに戻す
		addq.l	#4,a7
		move.l	d1,d0
		bra	getrealpath_return

getrealpath_thru:
		exg	a0,a1
		bsr	strcpy
		moveq	#0,d0
getrealpath_return:
		movem.l	(a7)+,d1/a0-a2
		rts
.endif
*****************************************************************
* lopen - 読み込みモードでファイルをオープンする
*         シンボリック・リンクはリンク自体をオープンする
*         デバイスはオープンしない
*
* CALL
*      A0     オープンするファイル名
*
* RETURN
*      D0.L   オープンしたファイルハンドル．またはDOSエラー・コード
*****************************************************************
lopen:
		movem.l	d1/a2-a3,-(a7)
		bsr	lgetmode
		bmi	lopen_return			*  ファイルは無い

		btst	#MODEBIT_LNK,d0
		beq	lopen_normal			*  SYMLINKではない -> 通常の OPEN

		move.l	lndrv,d0			*  lndrvが常駐していないなら
		beq	lopen_normal			*  通常の OPEN

		movea.l	d0,a2
		movea.l	LNDRV_realpathcpy(a2),a3
		clr.l	-(a7)
		DOS	_SUPER				*  スーパーバイザ・モードに切り換える
		addq.l	#4,a7
		move.l	d0,-(a7)			*  前の SSP の値
		movem.l	d2-d7/a0-a6,-(a7)
		move.l	a0,-(a7)
		pea	pathname_buf(pc)
		jsr	(a3)
		addq.l	#8,a7
		movem.l	(a7)+,d2-d7/a0-a6
		moveq	#ENOFILE,d1
		tst.l	d0
		bmi	lopen_link_done

		movem.l	d2-d7/a0-a6,-(a7)
		lea	pathname_buf(pc),a0
		bsr	strip_excessive_slashes
		clr.w	-(a7)
		move.l	a0,-(a7)
		movea.l	a7,a6
		movea.l	LNDRV_O_OPEN(a2),a3
		jsr	(a3)
		addq.l	#6,a7
		movem.l	(a7)+,d2-d7/a0-a6
		move.l	d0,d1
lopen_link_done:
		DOS	_SUPER				*  ユーザ・モードに戻す
		addq.l	#4,a7
		move.l	d1,d0
		bra	lopen_return

lopen_normal:
		clr.w	-(a7)
		move.l	a0,-(a7)
		DOS	_OPEN
		addq.l	#6,a7
		tst.l	d0
lopen_return:
		movem.l	(a7)+,d1/a2-a3
		rts
*****************************************************************
fgetdate:
		clr.l	-(a7)
		move.w	d0,-(a7)
		DOS	_FILEDATE
		addq.l	#6,a7
lgetdate_return:
		cmp.l	#$ffff0000,d0
		rts
*****************************************************************
lgetdate:
		bsr	lopen
		bmi	lgetdate_return

		move.l	d1,-(a7)
		move.l	d0,d1
		bsr	fgetdate
		exg	d0,d1
		bsr	fclose
		move.l	d1,d0
		move.l	(a7)+,d1
		bra	lgetdate_return
*****************************************************************
* is_identical - 2つのファイルが同一かどうか調べる
*
* CALL
*      A0     pathname of file 1
*      A1     pathname of file 2
*
* RETURN
*      CCR    同一ならば EQ
*      D0/A2-A3  破壊
*****************************************************************
is_identical:
		lea	target_fatchkbuf(pc),a2
		bsr	fatchk
		bmi	is_identical_return		* NE

		movea.l	a2,a3
		lea	source_fatchkbuf(pc),a2
		exg	a0,a1
		bsr	fatchk
		exg	a0,a1
		bmi	is_identical_return		*  NE

		cmpm.w	(a2)+,(a3)+
		bne	is_identical_return		*  NE

		cmpm.l	(a2)+,(a3)+
is_identical_return:
		rts
*****************************************************************
fatchk:
		move.l	a2,d0
		bset	#31,d0
		move.w	#14,-(a7)
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_FATCHK
		lea	10(a7),a7
		cmp.l	#EBADPARAM,d0
		bne	fatchk_return

		moveq	#0,d0
fatchk_return:
		tst.l	d0
		rts
*****************************************************************
is_chrdev:
		movem.l	d0,-(a7)
		move.w	d0,-(a7)
		clr.w	-(a7)
		DOS	_IOCTRL
		addq.l	#4,a7
		tst.l	d0
		bpl	is_chrdev_1

		moveq	#0,d0
is_chrdev_1:
		btst	#7,d0
		movem.l	(a7)+,d0
		rts
****************************************************************
* cat_pathname_x - concatinate head and tail
*
* CALL
*      A0     result buffer (MAXPATH+1バイト必要)
*      A1     points head
*      A2     points tail
*
* RETURN
*      A1     next word
*      A2     破壊
*      A3     tail pointer of result buffer
*      D0.L   positive if success.
*      CCR    TST.L D0
*****************************************************************
cat_pathname_x:
		bsr	cat_pathname
		bpl	cat_pathname_x_return

		lea	msg_too_long_pathname(pc),a2
		bsr	werror_myname_word_colon_msg
		tst.l	d0
cat_pathname_x_return:
		rts
*****************************************************************
* is_directory - 名前がディレクトリであるかどうかを調べる
*
* CALL
*      A0     名前
*
* RETURN
*      D0.L   名前/*.* が長すぎるならば -1．
*             このときエラーメッセージが表示され，D6.L には 2 がセットされる．
*
*             そうでなければ，名前がディレクトリならば 1，さもなくば 0
*
*      CCR    TST.L D0
*****************************************************************
is_directory:
		movem.l	a0-a3,-(a7)
		tst.b	(a0)
		beq	is_directory_false

		movea.l	a0,a1
		lea	pathname_buf(pc),a0
		lea	dos_wildcard_all(pc),a2
		bsr	cat_pathname_x
		bmi	is_directory_return

		move.w	#MODEVAL_ALL,-(a7)		*  すべてのエントリを検索する
		move.l	a0,-(a7)
		pea	filesbuf(pc)
		DOS	_FILES
		lea	10(a7),a7
		tst.l	d0
		bpl	is_directory_true

		cmp.l	#ENOFILE,d0
		beq	is_directory_true
is_directory_false:
		moveq	#0,d0
		bra	is_directory_return

is_directory_true:
		moveq	#1,d0
is_directory_return:
		movem.l	(a7)+,a0-a3
		rts
*****************************************************************
werror_myname:
		move.l	a0,-(a7)
		lea	msg_myname(pc),a0
		bsr	werror
		movea.l	(a7)+,a0
		rts
*****************************************************************
werror_myname_and_msg:
		bsr	werror_myname
werror:
		movem.l	d0/a1,-(a7)
		movea.l	a0,a1
werror_1:
		tst.b	(a1)+
		bne	werror_1

		subq.l	#1,a1
		suba.l	a0,a1
		move.l	a1,-(a7)
		move.l	a0,-(a7)
		move.w	#2,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		movem.l	(a7)+,d0/a1
		rts
*****************************************************************
werror_newline:
		move.l	a0,-(a7)
		lea	msg_newline(pc),a0
		bsr	werror
		movea.l	(a7)+,a0
		rts
*****************************************************************
werror_myname_word_colon_msg:
		bsr	werror_myname_and_msg
		move.l	a0,-(a7)
		lea	msg_colon(pc),a0
		bsr	werror
		movea.l	a2,a0
		bsr	werror
		movea.l	(a7)+,a0
werror_newline_and_set_error:
		bsr	werror_newline
		moveq	#2,d6
		btst	#FLAG_e,d5
		bne	exit_program

		rts
*****************************************************************
perror:
		movem.l	d0/a2,-(a7)
		not.l	d0		* -1 -> 0, -2 -> 1, ...
		cmp.l	#25,d0
		bls	perror_2

		moveq	#0,d0
perror_2:
		lea	perror_table(pc),a2
		lsl.l	#1,d0
		move.w	(a2,d0.l),d0
		lea	sys_errmsgs(pc),a2
		lea	(a2,d0.w),a2
		bsr	werror_myname_word_colon_msg
		movem.l	(a7)+,d0/a2
		tst.l	d0
		rts
*****************************************************************
.data

	dc.b	0
	dc.b	'## mv 1.5 ##  Copyright(C)1992-93 by Itagaki Fumihiko',0

.even
perror_table:
	dc.w	msg_error-sys_errmsgs			*   0 ( -1)
	dc.w	msg_nofile-sys_errmsgs			*   1 ( -2)
	dc.w	msg_nofile-sys_errmsgs			*   2 ( -3)
	dc.w	msg_too_many_openfiles-sys_errmsgs	*   3 ( -4)
	dc.w	msg_dirvol-sys_errmsgs			*   4 ( -5)
	dc.w	msg_error-sys_errmsgs			*   5 ( -6)
	dc.w	msg_error-sys_errmsgs			*   6 ( -7)
	dc.w	msg_error-sys_errmsgs			*   7 ( -8)
	dc.w	msg_error-sys_errmsgs			*   8 ( -9)
	dc.w	msg_error-sys_errmsgs			*   9 (-10)
	dc.w	msg_error-sys_errmsgs			*  10 (-11)
	dc.w	msg_error-sys_errmsgs			*  11 (-12)
	dc.w	msg_bad_name-sys_errmsgs		*  12 (-13)
	dc.w	msg_error-sys_errmsgs			*  13 (-14)
	dc.w	msg_bad_drive-sys_errmsgs		*  14 (-15)
	dc.w	msg_error-sys_errmsgs			*  15 (-16)
	dc.w	msg_error-sys_errmsgs			*  16 (-17)
	dc.w	msg_error-sys_errmsgs			*  17 (-18)
	dc.w	msg_write_disabled-sys_errmsgs		*  18 (-19)	CREATE
	dc.w	msg_error-sys_errmsgs			*  19 (-20)
	dc.w	msg_error-sys_errmsgs			*  20 (-21)
	dc.w	msg_file_exists-sys_errmsgs		*  21 (-22)
	dc.w	msg_disk_full-sys_errmsgs		*  22 (-23)
	dc.w	msg_directory_full-sys_errmsgs		*  23 (-24)
	dc.w	msg_error-sys_errmsgs			*  24 (-25)
	dc.w	msg_error-sys_errmsgs			*  25 (-26)

sys_errmsgs:
msg_error:			dc.b	'エラー',0
msg_nofile:			dc.b	'このようなファイルやディレクトリはありません',0
msg_dirvol:			dc.b	'ディレクトリかボリューム・ラベルです',0
msg_too_many_openfiles:		dc.b	'オープンしているファイルが多すぎます',0
msg_bad_name:			dc.b	'名前が無効です',0
msg_bad_drive:			dc.b	'ドライブの指定が無効です',0
msg_write_disabled:		dc.b	'書き込みが許可されていません',0
msg_semicolon_directory_full:	dc.b	'; '
msg_directory_full:		dc.b	'ディレクトリが満杯です',0
msg_semicolon_file_exists:	dc.b	'; '
msg_file_exists:		dc.b	'ファイルが存在しています',0
msg_disk_full:			dc.b	'ディスクが満杯です',0

msg_myname:			dc.b	'mv'
msg_colon:			dc.b	': ',0
msg_dos_version_mismatch:	dc.b	'バージョン2.00以降のHuman68kが必要です',CR,LF,0
msg_no_memory:			dc.b	'メモリが足りません',CR,LF,0
msg_illegal_option:		dc.b	'不正なオプション -- ',0
msg_bad_arg:			dc.b	'引数が正しくありません',0
msg_too_few_args:		dc.b	'引数が足りません',0
msg_too_long_pathname:		dc.b	'パス名が長過ぎます',0
msg_nodir:			dc.b	'ディレクトリがありません',0
msg_not_a_directory:		dc.b	'ディレクトリではありません',0
msg_destination:		dc.b	' の移動先 ',0
msg_ni:				dc.b	' に',0
msg_readonly:			dc.b	'書き込み禁止',0
msg_hidden:			dc.b	'隠し',0
msg_system:			dc.b	'システム',0
msg_file:			dc.b	'ファイル',0
msg_vollabel:			dc.b	'ボリューム・ラベル',0
msg_symlink:			dc.b	'シンボリック・リンク',0
msg_confirm_replace:		dc.b	'が存在しています．消去して移動しますか？ ',0
msg_wo:				dc.b	' を ',0
msg_confirm_move:		dc.b	' に移動しますか？ ',0
msg_cannot_move:		dc.b	' に移動できません',0
msg_directory_exists:		dc.b	'; 移動先にディレクトリが存在しています',0
msg_cannot_move_dir_to_its_sub:	dc.b	'; ディレクトリをそのサブディレクトリ下に移動することはできません',0
msg_cannot_move_dirvol_across:	dc.b	'; ディレクトリやボリューム・ラベルを別のドライブに移動することはできません',0
msg_drive_differ:		dc.b	'; ドライブが異なります',0
msg_usage:			dc.b	CR,LF
	dc.b	'使用法:  mv [-Ifiuvx] [-m <属性変更式>] [--] <旧パス名> <新パス名>',CR,LF
	dc.b	'         mv [-Iefiuvx] [-m <属性変更式>] [--] <ファイル> ... <移動先>',CR,LF,CR,LF
	dc.b	'         属性変更式: {[ugoa]{{+-=}[ashrwx]}...}[,...]'
msg_newline:			dc.b	CR,LF
msg_nul:			dc.b	0
msg_arrow:			dc.b	' -> ',0
dos_wildcard_all:		dc.b	'*.*',0
*****************************************************************
.bss

.even
lndrv:			ds.l	1
.even
source_fatchkbuf:	ds.b	14+8			*  +8 : fatchkバグ対策
.even
target_fatchkbuf:	ds.b	14+8			*  +8 : fatchkバグ対策
.even
filesbuf:		ds.b	STATBUFSIZE
.even
getsbuf:		ds.b	2+GETSLEN+1
pathname_buf:		ds.b	128
new_pathname:		ds.b	MAXPATH+1
nameck_buffer1:		ds.b	91
nameck_buffer2:		ds.b	91
stdin_is_terminal:	ds.b	1
mode_mask:		ds.b	1
mode_plus:		ds.b	1
.even
			ds.b	STACKSIZE
.even
stack_bottom:
*****************************************************************

.end start
