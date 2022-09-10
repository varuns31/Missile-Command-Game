
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
eax_save: .long 0x0


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
	jmp check_exploding
DONE:
	movl mp1_missile_list,%ebx
	jmp moved_off_screen
Back_from_jump:
	jmp explosion_now
Back_from_explosions:

		ret

explosion_now:
	movl mp1_missile_list,%ebx
	cmpl $0,%ebx
	je Back_from_explosions
	movl 4(%ebx),%esi
	movl 20(%ebx),%edi
	cmpl %esi,%edi
	je cont_explosion
	movl (%ebx),%ebx

cont_explosion:
	movl 8(%ebx),%esi
	movl 24(%ebx),%edi
	je exploded_missile
	movl 28(%ebx),%esi
	cmpl $0,%esi
	ja exploded_missile
	movl (%ebx),%ebx	
	jmp explosion_now

exploded_missile:
	pushl %ebx
	call missile_explode
	popl %ebx
	subl $1,28(%ebx)
	cmpl $0,28(%ebx)
	je exploded_missile_remove
	movl (%ebx),%ebx	
	jmp explosion_now # Exploding missile to be drawn later

exploded_missile_remove:
	movl %eax,eax_save
	pushl %ebx
	call mp1_missile_remove
	popl %ebx
	movl %eax,%ebx
	movl eax_save,%eax
	jmp explosion_now 

moved_off_screen:
	cmpl $0,%ebx
	je Back_from_jump
	cmpl $79,4(%ebx)
	ja remove_missile_moved_off_screen
	cmpl $24,8(%ebx)
	ja remove_missile_moved_off_screen
	movl (%ebx),%ebx
	jmp moved_off_screen

remove_missile_moved_off_screen:
	movl %eax,eax_save
	pushl %ebx
	call mp1_missile_remove
	popl %ebx
	movl %eax,%ebx
	movl eax_save,%eax
	jmp moved_off_screen

check_exploding:
	movl mp1_missile_list,%esi #head of linked list
	cmpl $0,%esi #head is 0
	je DONE
	movl 28(%esi),%ebx
	cmpl $0,%ebx #exploded=0
	je NEXT_MISSLE
	movl 4(%esi),%ebx # x=x+VX
	movl 12(%esi),%edi
	addl %edi,%ebx
	movl %ebx,4(%esi)
	movl 8(%esi),%ebx # y=y+vy
	movl 16(%esi),%edi
	addl %edi,%ebx
	movl %ebx,8(%esi)
NEXT_MISSLE:
	movl (%esi),%esi
	jmp check_exploding



mp1_missile_remove: # void* remove(void* ptr) returns pointer to next of deleted pointer
	pushl %ebp
	movl  %esp,%ebp
	pushl %ebx
	pushl %esi
	pushl %edi
	movl 4(%ebp),%ebx # ebx= pointer of missile to remove
	movl mp1_missile_list,%esi # esi=head of linked list
	cmpl %esi,%ebx # head needs to be removed
	je change_head
LOOP:
	cmpl (%esi),%ebx #finding prev of pointer to be removed
	je remove_missile
	movl (%esi),%esi
	jmp LOOP

remove_missile:
	movl (%ebx),%edi # edi = ebx->next
	movl %edi,(%esi) # prev->next=temp->next
	pushl %ebx
	call mp1_free
	popl %ebx
	jmp return_missile_remove

return_missile_remove:
	popl %edi
	popl %esi
	popl %ebx
	movl %edi,%eax
	leave 
	ret

change_head:
	movl (%esi),%edi
	movl %edi,mp1_missile_list
	pushl %esi
	call mp1_free
	popl %esi
	jmp return_missile_remove




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
	movl 8(%ebp),%ebx
	cmpl $0,%ebx
	jl RET_INVALID
	cmpl $4,%ebx
	ja RET_INVALID
	jmp *jmptable(,%ebx,4)
RETURN_NOW:
		popl %edi
		popl %esi
		popl %ebx
		leave 	
		ret

RET_INVALID:
	movl $-1,%eax
	jmp RETURN_NOW

RET_ZERO:
	movl $0,%eax
	jmp RETURN_NOW

# ----------------- Functions private to this file -------------------

update_missiles:
		ret

mp1_ioctl_startgame:
	movl $40,crosshairs_x
	movl $12,crosshairs_y
	jmp RETURN_NOW

mp1_ioctl_addmissile:
	
		ret

mp1_ioctl_movexhairs:
	movw 4(%ebp),%bx
	movw 6(%ebp),%si
	movl crosshairs_x,%edi
	addw %bx,%di
	cmpl $79,%edi
	jb VALID_X
	subw %bx,%di
VALID_X: 
	movl %edi,crosshairs_x
	movl crosshairs_y,%edi
	addw %si,%di
	cmpl $24,%edi
	jb VALID_Y
	subw %si,%di
VALID_Y:
	movl %edi,crosshairs_y
	jmp RET_ZERO

mp1_ioctl_getstatus:
	movl 4(%ebp),%ebx
	andl $0,%esi
	movw mp1_score,%si
	movw %si,(%ebx)
	jmp RET_ZERO

mp1_ioctl_endgame:
		ret

jmptable:
	.long mp1_ioctl_startgame,mp1_ioctl_addmissile,mp1_ioctl_movexhairs,mp1_ioctl_getstatus,mp1_ioctl_endgame
	