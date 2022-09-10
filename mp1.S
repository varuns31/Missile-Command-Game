# mp1.S - missile-command version
# Good luck, and have fun!

.data
	
    # Constants for accessing the fields of a struct missile, 
    # struct missile is defined in rtc.h and mp1.h

	NEXT 	  = 0
	X	  = 4
	Y	  = 8
	VX	  = 12
	VY	  = 16
	DEST_X	  = 20
	DEST_Y	  = 24
	EXPLODED  = 28
	C	  = 32

    # Character to draw for an explosion - '@'

	EXPLOSION = 64


# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl mp1_missile_list, base_alive, mp1_score

mp1_missile_list:	.long 0x0	# Head of list pointer
base_alive:		.long 0x0	# Array of 3 bytes, plus a padding byte
mp1_score:		.long 0x0	# Player's current score


# Data private to this  file

base_pic:     	    .string "/^^^\\"	# Picture of a live base
dead_base_pic: 	    .string "xxxxx"	# Picture of a dead base
crosshairs_x:		.long 0x0	# X-position of the crosshairs
crosshairs_y:		.long 0x0	# Y-position of the crosshairs

.text

# void mp1_poke(void);
# You can use this function to write to video memory.
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:
		movl    vmem_base_addr(,1),%edx
		movb    %cl,(%edx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long garbage);
# Performs three tasks:
#	(1) updates the list of missiles (implement this in update_missiles,
#           below, and call it from here).
#	(2) Redraw the bases - they may have been overwritten with missiles
#	(3) Redraw the crosshairs - it may have been overwritten with missiles
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet
mp1_rtc_tasklet:
	pushl %ebp
	movl  %esp,%ebp
	pushl %ebx
	pushl %esi
	pushl %edi
	jmp redraw_crosshairs
	
leave_tasklet:
		popl %edi
		popl %esi
		popl %ebx
		leave 
		ret
redraw_crosshairs:
	pushl %eax
	pushl %esi
	pushl %ecx
	movl crosshairs_x,%esi 
	imull $160,%esi,%eax # 80*2*crosshairs_x=eax
	movl crosshairs_y,%esi # esi=crosshairs_y
	imull $2,%esi 
	addl %esi,%eax # eax=eax+2*crosshairs_y
	movb $43,%cl #print hash for crosshairs
	pushl %edx
	call mp1_poke
	popl %edx
	popl %ecx
	popl %esi
	popl %eax
	jmp leave_tasklet


# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function 
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl
mp1_ioctl:
	pushl %ebp
	movl  %esp,%ebp
	pushl %ebx
	pushl %esi
	pushl %edi
	movl 12(%ebp),%ebx #command=ebx
	cmpl $0,%ebx
	jl RET_INVALID 
	cmpl $4,%ebx
	ja RET_INVALID
	jmp *jmptable(,%ebx,4)

RET_INVALID:
	movl $-1,%eax
	jmp RETURN_NOW

RETURN_NOW:
		popl %edi
		popl %esi
		popl %ebx
		leave 	
		ret

RET_ZERO:
	#movl $0,%eax
	jmp RETURN_NOW

# ----------------- Functions private to this file -------------------

update_missiles:
		jmp RETURN_NOW

mp1_ioctl_startgame:
    movl $12,crosshairs_x
	movl $40,crosshairs_y
		jmp RETURN_NOW

mp1_ioctl_addmissile:
		jmp RETURN_NOW

mp1_ioctl_movexhairs:
	jmp remove_crosshairs
update_cross_hair:
	movw 10(%ebp),%bx #lower 16 bits of argument
	movw 8(%ebp),%si #upper 16 bits of argument
	movl crosshairs_x,%edi # current crosshairs_x
	addw %bx,%di #add lower 16 bits to crosshairs_x
	cmpl $25,%edi #compare to 79
	jb VALID_X #move ahead if valid
	subw %bx,%di #subtract again if invalid
VALID_X: 
	movl %edi,crosshairs_x #update crosshairs_x
	movl crosshairs_y,%edi 
	addw %si,%di #update crosshairs_y
	cmpl $80,%edi
	jb VALID_Y
	subw %si,%di #subtract again if invalid
VALID_Y:
	movl %edi,crosshairs_y
	jmp RET_ZERO

mp1_ioctl_getstatus:
		jmp RETURN_NOW

mp1_ioctl_endgame:
		jmp RETURN_NOW

jmptable:
	.long mp1_ioctl_startgame,mp1_ioctl_addmissile,mp1_ioctl_movexhairs,mp1_ioctl_getstatus,mp1_ioctl_endgame

remove_crosshairs:
	pushl %eax
	pushl %esi
	pushl %ecx
	movl crosshairs_x,%esi
	imull $160,%esi,%eax
	movl crosshairs_y,%esi
	imull $2,%esi
	addl %esi,%eax
	movb $32,%cl
	call mp1_poke #print " " for original crosshairs
	popl %ecx
	popl %esi
	popl %eax
	jmp update_cross_hair
