* mv - move file
*
* Itagaki Fumihiko 30-Aug-92  Create.
*
* Usage: mv [ -fiuvx ] <�t�@�C��1> <�t�@�C��2>
*        mv [ -fiuvx ] <�f�B���N�g��1> <�f�B���N�g��2>
*        mv [ -fiuvx ] <�t�@�C��> ... <�f�B���N�g��>

.include doscall.h
.include error.h
.include limits.h
.include stat.h
.include chrcode.h

.xref DecodeHUPAIR
.xref getlnenv
.xref issjis
.xref strlen
.xref strfor1
.xref headtail
.xref cat_pathname
.xref strip_excessive_slashes
.xref fclose

REQUIRED_OSVER	equ	$200			*  2.00�ȍ~

STACKSIZE	equ	512
GETSLEN		equ	32

FLAG_f		equ	0
FLAG_i		equ	1
FLAG_u		equ	2
FLAG_v		equ	3
FLAG_x		equ	4

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
		lea	stack_bottom,a7			*  A7 := �X�^�b�N�̒�
		DOS	_VERNUM
		cmp.w	#REQUIRED_OSVER,d0
		bcs	dos_version_mismatch

		DOS	_GETPDB
		movea.l	d0,a0				*  A0 : PDB�A�h���X
		move.l	a7,d0
		sub.l	a0,d0
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_SETBLOCK
		addq.l	#8,a7
	*
	*  �������ъi�[�G���A���m�ۂ���
	*
		lea	1(a2),a0			*  A0 := �R�}���h���C���̕�����̐擪�A�h���X
		bsr	strlen				*  D0.L := �R�}���h���C���̕�����̒���
		addq.l	#1,d0
		bsr	malloc
		bmi	insufficient_memory

		movea.l	d0,a1				*  A1 := �������ъi�[�G���A�̐擪�A�h���X
	*
	*  �o�b�t�@���m�ۂ���
	*
		move.l	#$00ffffff,d0
		bsr	malloc
		sub.l	#$81000000,d0
		cmp.l	#1024,d0
		blo	insufficient_memory

		move.l	d0,d4				*  D4.L : �o�b�t�@�T�C�Y
		bsr	malloc
		bmi	insufficient_memory

		movea.l	d0,a4				*  A4 : �o�b�t�@
	*
	*  lndrv ���g�ݍ��܂�Ă��邩�ǂ�������������
	*
		bsr	getlnenv
		move.l	d0,lndrv
	*
	*  �������f�R�[�h���C���߂���
	*
		bsr	DecodeHUPAIR			*  �������f�R�[�h����
		movea.l	a1,a0				*  A0 : �����|�C���^
		move.l	d0,d7				*  D7.L : �����J�E���^
		moveq	#0,d5				*  D5.L : flags
decode_opt_loop1:
		tst.l	d7
		beq	decode_opt_done

		cmpi.b	#'-',(a0)
		bne	decode_opt_done

		subq.l	#1,d7
		addq.l	#1,a0
		move.b	(a0)+,d0
		beq	decode_opt_done
decode_opt_loop2:
		cmp.b	#'f',d0
		beq	set_option_f

		cmp.b	#'i',d0
		beq	set_option_i

		moveq	#FLAG_u,d1
		cmp.b	#'u',d0
		beq	set_option

		moveq	#FLAG_v,d1
		cmp.b	#'v',d0
		beq	set_option

		moveq	#FLAG_x,d1
		cmp.b	#'x',d0
		beq	set_option

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

set_option_f:
		bset	#FLAG_f,d5
		bclr	#FLAG_i,d5
		bra	set_option_done

set_option_i:
		bset	#FLAG_i,d5
		bclr	#FLAG_f,d5
		bra	set_option_done

set_option:
		bset	d1,d5
set_option_done:
		move.b	(a0)+,d0
		bne	decode_opt_loop2
		bra	decode_opt_loop1

decode_opt_done:
		subq.l	#2,d7
		bcs	too_few_args
	*
	*  �W�����͂��[���ł��邩�ǂ����𒲂ׂĂ���
	*
		moveq	#0,d0				*  �W�����͂�
		bsr	is_chrdev			*  �L�����N�^�f�o�C�X
		sne	stdin_is_terminal
	*
	*  �����J�n
	*
		moveq	#0,d6				*  D6.W : �G���[�E�R�[�h
	*
	*  ������ 2�ȏ� -> target�𒲂ׂ�
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
		bmi	exit_program
		bne	mv_into_dir

		*  target �̓f�B���N�g���ł͂Ȃ�

		tst.l	d7
		bne	bad_destination

		exg	a0,a1				*  A0 : 1st source, A1 : target
		bsr	strip_excessive_slashes
		bsr	move_file
		bra	exit_program
****************
mv_into_dir:
		exg	a0,a1				*  A0 : 1st source, A1 : target
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

bad_destination:
		lea	msg_not_a_directory(pc),a2
		bsr	lgetmode
		bpl	mv_error_exit

		lea	msg_nodir(pc),a2
mv_error_exit:
		bsr	werror_myname_word_colon_msg
		bra	exit_program

too_few_args:
		lea	msg_too_few_args(pc),a0
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
*      A0 �Ŏ������G���g���� A1 �Ŏ������f�B���N�g�����Ɉړ�����
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
* move_file
*
*      A0 �Ŏ������p�X�̃t�@�C���� A1 �Ŏ������p�X�Ɉړ�����
*
* CALL
*      A0     source
*      A1     target
*
* RETURN
*      D0-D3/A0-A3  �j��
*****************************************************************
move_file:
		*  source �𒲂ׂ�
		bsr	lgetmode
		bmi	perror

		move.l	d0,d1				*  D1.L : source �� mode

		*  target �𒲂ׂ�
		exg	a0,a1				*  A0:target, A1:source
		bsr	lgetmode
		move.l	d0,d2				*  D2.L : target �� mode
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
		*  target�����݂���

		*  target��source�Ɠ���Ȃ�C����͑��݂��Ȃ����̂ƌ��Ȃ�
		lea	target_fatchkbuf(pc),a2
		bsr	fatchk
		movea.l	a2,a3
		lea	source_fatchkbuf(pc),a2
		exg	a0,a1
		bsr	fatchk
		exg	a0,a1
		cmpm.w	(a2)+,(a3)+
		bne	move_file_not_identical

		cmpm.l	(a2)+,(a3)+
		beq	move_file_new
move_file_not_identical:
		*  target���f�B���N�g���Ȃ�G���[
		lea	msg_directory_exists(pc),a2
		btst	#MODEBIT_DIR,d2
		bne	move_error

		btst	#MODEBIT_DIR,d1
		bne	update_ok

		btst	#FLAG_u,d5
		beq	update_ok

		bsr	lgetdate
		bcc	update_ok

		move.l	d0,d3				*  D3.L : target �̃^�C���E�X�^���v
		exg	a0,a1
		bsr	lgetdate			*  D0.L : source �̃^�C���E�X�^���v
		exg	a0,a1
		bcc	update_ok

		cmp.l	d3,d0
		bls	move_file_return
update_ok:
		bsr	confirm_file
		bne	move_file_return

		*  target ���폜����
		bsr	unlink
			* �G���[�����ȗ�
		moveq	#-1,d2
move_file_new:
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
		*  �ړ�����
		exg	a0,a1				*  A0:source, A1:target
		moveq	#MODEVAL_ARC,d0
		bsr	lchmod
		bmi	perror

		move.l	a1,-(a7)
		move.l	a0,-(a7)
		DOS	_RENAME
		addq.l	#8,a7
		move.l	d0,d2
		bmi	simple_move_failed

		movea.l	a1,a0
		move.l	d1,d0
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
	*  �G���[
	*  �l�����錴���i���o����鏇�j:-
	*  o �V�p�X�������� ... EBADNAME
	*  o �h���C�u���Ⴄ ... EBADDRV
	*  o �V�p�X���̓r���̃f�B���N�g�������݂��Ȃ� ... ENODIR
	*  o �f�B���N�g�������̃T�u�f�B���N�g���Ɉړ����悤�Ƃ��� ... ENODIR
	*  o �t�@�C�������݂��� ... EMVEXISTS
	*  o �f�B���N�g�����{�����[���E���x����ʂ̃f�B���N�g���Ɉړ����悤�Ƃ��� ... EWRITE
	*  o �f�B���N�g������t ... EDIRFULL
	*
		move.l	d1,d0
		bsr	lchmod
		bmi	perror

		move.l	d2,d0
		exg	a0,a1				*  A0:target, A1:source
		cmp.l	#ENODIR,d0
		bne	simple_move_failed_1

		bsr	lgetmode
		cmp.l	d2,d0
		beq	perror

		lea	msg_cannot_move_dir_to_sub(pc),a2
		bra	move_error

simple_move_failed_1:
		cmp.l	#EBADNAME,d0
		beq	perror

		cmp.l	#EMVEXISTS,d0
		beq	perror

		cmp.l	#EDIRFULL,d0
		beq	perror

		lea	msg_nul(pc),a2
		cmp.l	#EBADDRV,d0
		bne	move_error

		lea	msg_cannot_move_dirvol_across(pc),a2
		btst	#MODEBIT_VOL,d1
		bne	move_error

		btst	#MODEBIT_DIR,d1
		bne	move_error
	*
	*  �h���C�u���قȂ�
	*
		lea	msg_drive_differ(pc),a2
		btst	#FLAG_x,d5
		bne	move_error
		*
		*  source �� open ����
		*
		exg	a0,a1				*  A0:source, A1:target
		bsr	lopen				*  source ���I�[�v������
		bmi	perror

		move.l	d0,d2				*  D2.L : source �̃t�@�C���E�n���h��
		*
		*  target �� create ����
		*
		move.w	d1,-(a7)			*  source �� mode ��
		move.l	a1,-(a7)			*  target file ��
		DOS	_CREATE				*  �쐬����
		addq.l	#6,a7				*  �i�h���C�u�̌����͍ς�ł���j
		move.l	d0,d1				*  D1.L : target �̃t�@�C���E�n���h��
		bmi	copy_file_perror_2
		*
		*  �t�@�C���̓��e���R�s�[����
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
		*  �t�@�C���̃^�C���X�^���v���R�s�[����
		*
		move.w	d2,d0
		bsr	fgetdate
		bcc	copy_timestamp_done

		move.l	d0,-(a7)
		move.w	d1,-(a7)
		DOS	_FILEDATE
		addq.l	#6,a7
			* �G���[�����ȗ� (����)
copy_timestamp_done:
		move.w	d1,d0
		bsr	fclose
			* �G���[�����ȗ�
		move.w	d2,d0
		bsr	fclose
			* �G���[�����ȗ�
		*
		*  source ���폜����
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
		move.w	d2,d0				*  source ��
		bsr	fclose				*  close ����
		move.l	(a7)+,d0
		bra	perror

copy_file_disk_full:
		moveq	#EDISKFULL,d0
copy_file_perror_4:
		movea.l	a1,a0
copy_file_perror_3:
		move.l	d0,-(a7)
		move.w	d1,d0				*  target ��
		bsr	fclose				*  close ����
		move.l	(a7)+,d0
		bra	copy_file_perror_1
*****************************************************************
confirm_file:
		*  �W�����͂��[���Ȃ�΁C�{�����[���E���x���C�V���{���b�N�E�����N�C
		*  �ǂݍ��ݐ�p�C�B���C�V�X�e���̂ǂꂩ�̑����r�b�g��ON�ł���ꍇ�C
		*  �₢���킹��

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
		lea	msg_replace(pc),a0
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
* getrealpath - �V���{���b�N�E�����N�̎��̂̃p�X���𓾂�
*
* CALL
*      A0     �p�X��
*
* RETURN
*      pathname_buf   (A0) �������N�Ȃ�C���̎��̂̃p�X��
*                     �����łȂ���� (A0) ���R�s�[�����
*
*      D0.L   �G���[�Ȃ畉
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
		DOS	_SUPER				*  �X�[�p�[�o�C�U�E���[�h�ɐ؂芷����
		addq.l	#4,a7
		move.l	d0,-(a7)			*  �O�� SSP �̒l
		movem.l	d2-d7/a0-a6,-(a7)
		move.l	a0,-(a7)
		move.l	a1,-(a7)
		jsr	(a2)
		addq.l	#8,a7
		movem.l	(a7)+,d2-d7/a0-a6
		move.l	d0,d1
		DOS	_SUPER				*  ���[�U�E���[�h�ɖ߂�
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
* lopen - �ǂݍ��݃��[�h�Ńt�@�C�����I�[�v������
*         �V���{���b�N�E�����N�̓����N���̂��I�[�v������
*         �f�o�C�X�̓I�[�v�����Ȃ�
*
* CALL
*      A0     �I�[�v������t�@�C����
*
* RETURN
*      D0.L   �I�[�v�������t�@�C���n���h���D�܂���DOS�G���[�E�R�[�h
*****************************************************************
lopen:
		movem.l	d1/a2-a3,-(a7)
		bsr	lgetmode
		bmi	lopen_return			*  �t�@�C���͖���

		btst	#MODEBIT_LNK,d0
		beq	lopen_normal			*  SYMLINK�ł͂Ȃ� -> �ʏ�� OPEN

		move.l	lndrv,d0			*  lndrv���풓���Ă��Ȃ��Ȃ�
		beq	lopen_normal			*  �ʏ�� OPEN

		movea.l	d0,a2
		movea.l	LNDRV_realpathcpy(a2),a3
		clr.l	-(a7)
		DOS	_SUPER				*  �X�[�p�[�o�C�U�E���[�h�ɐ؂芷����
		addq.l	#4,a7
		move.l	d0,-(a7)			*  �O�� SSP �̒l
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
		DOS	_SUPER				*  ���[�U�E���[�h�ɖ߂�
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
fatchk:
		move.l	a2,d0
		bset	#31,d0
		move.w	#14,-(a7)
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_FATCHK
		lea	10(a7),a7
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
*      A0     result buffer (MAXPATH+1�o�C�g�K�v)
*      A1     points head
*      A2     points tail
*
* RETURN
*      A1     next word
*      A2     �j��
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
* is_directory - ���O���f�B���N�g���ł��邩�ǂ����𒲂ׂ�
*
* CALL
*      A0     ���O
*
* RETURN
*      D0.L   ���O/*.* ����������Ȃ�� -1�D
*             ���̂Ƃ��G���[���b�Z�[�W���\������CD6.L �ɂ� 2 ���Z�b�g�����D
*
*             �����łȂ���΁C���O���f�B���N�g���Ȃ�� 1�C�����Ȃ��� 0
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

		move.w	#MODEVAL_ALL,-(a7)		*  ���ׂẴG���g������������
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
	dc.b	'## mv 1.0 ##  Copyright(C)1992 by Itagaki Fumihiko',0

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
msg_error:			dc.b	'�G���[',0
msg_nofile:			dc.b	'���̂悤�ȃt�@�C����f�B���N�g���͂���܂���',0
msg_dirvol:			dc.b	'�f�B���N�g�����{�����[���E���x���ł�',0
msg_too_many_openfiles:		dc.b	'�I�[�v�����Ă���t�@�C�����������܂�',0
msg_bad_name:			dc.b	'���O�������ł�',0
msg_bad_drive:			dc.b	'�h���C�u�̎w�肪�����ł�',0
msg_write_disabled:		dc.b	'�������݂�������Ă��܂���',0
msg_directory_full:		dc.b	'�f�B���N�g�������t�ł�',0
msg_file_exists:		dc.b	'�t�@�C�������݂��Ă��܂�',0
msg_disk_full:			dc.b	'�f�B�X�N�����t�ł�',0

msg_myname:			dc.b	'mv'
msg_colon:			dc.b	': ',0
msg_dos_version_mismatch:	dc.b	'�o�[�W����2.00�ȍ~��Human68k���K�v�ł�',CR,LF,0
msg_no_memory:			dc.b	'������������܂���',CR,LF,0
msg_illegal_option:		dc.b	'�s���ȃI�v�V���� -- ',0
msg_too_few_args:		dc.b	'����������܂���',0
msg_too_long_pathname:		dc.b	'�p�X�������߂��܂�',0
msg_nodir:			dc.b	'�f�B���N�g��������܂���',0
msg_not_a_directory:		dc.b	'�f�B���N�g���ł͂���܂���',0
msg_destination:		dc.b	'�ړ���g',0
msg_ni:				dc.b	'�h��',0
msg_readonly:			dc.b	'�������݋֎~',0
msg_hidden:			dc.b	'�B��',0
msg_system:			dc.b	'�V�X�e��',0
msg_file:			dc.b	'�t�@�C��',0
msg_vollabel:			dc.b	'�{�����[�����x��',0
msg_symlink:			dc.b	'�V���{���b�N�E�����N',0
msg_replace:			dc.b	'�����݂��Ă��܂��D�������܂����H',0
msg_wo:				dc.b	' �� ',0
msg_cannot_move:		dc.b	' �Ɉړ��ł��܂���',0
msg_directory_exists:		dc.b	'; �ړ���Ƀf�B���N�g�������݂��Ă��܂�',0
msg_cannot_move_dir_to_sub:	dc.b	'; �f�B���N�g�������̃T�u�f�B���N�g�����Ɉړ����邱�Ƃ͂ł��܂���',0
msg_cannot_move_dirvol_across:	dc.b	'; �f�B���N�g����{�����[���E���x����ʂ̃h���C�u�Ɉړ����邱�Ƃ͂ł��܂���',0
msg_drive_differ:		dc.b	'; �h���C�u���قȂ�܂�',0
msg_usage:			dc.b	CR,LF
	dc.b	'�g�p�@:  mv [-fiuvx] [-] <���p�X��> <�V�p�X��>',CR,LF
	dc.b	'         mv [-fiuvx] [-] <�t�@�C��> ... <�ړ���>'
msg_newline:			dc.b	CR,LF
msg_nul:			dc.b	0
msg_arrow:			dc.b	' -> ',0
dos_wildcard_all:		dc.b	'*.*',0
*****************************************************************
.bss

lndrv:			ds.l	1
source_fatchkbuf:	ds.b	14
target_fatchkbuf:	ds.b	14
.even
filesbuf:		ds.b	STATBUFSIZE
.even
getsbuf:		ds.b	2+GETSLEN+1
pathname_buf:		ds.b	128
new_pathname:		ds.b	MAXPATH+1
stdin_is_terminal:	ds.b	1
.even
			ds.b	STACKSIZE
.even
stack_bottom:
*****************************************************************

.end start