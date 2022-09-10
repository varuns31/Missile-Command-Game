
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
	movl mp1_missile_list,%ebx
	jmp explosion_now
Back_from_explosions:
	jmp redraw_crosshairs
	
leave_tasklet:
		popl %edi
		popl %esi
		popl %ebx
		leave 
		ret

explosion_now:
	cmpl $0,%ebx #head==NULL
	je Back_from_explosions
	movl X(%ebx),%esi
	movl DEST_X(%ebx),%edi
	cmpl %esi,%edi # x==DEST_X
	je cont_explosion
	movl EXPLODED(%ebx),%esi #exploded is not equal to 0
	cmpl $0,%esi
	ja exploded_missile
	movl (%ebx),%ebx
	jmp explosion_now #check next missile

cont_explosion:
	movl Y(%ebx),%esi
	movl DEST_Y(%ebx),%edi
	je exploded_missile #y==DEST_Y
	movl EXPLODED(%ebx),%esi #exploded is not equal to 0
	cmpl $0,%esi
	ja exploded_missile
	movl (%ebx),%ebx	
	jmp explosion_now #check next missile

exploded_missile:
	pushl %ebx
	call missile_explode
	popl %ebx
	subl $1,28(%ebx) #exploded--
	cmpl $0,28(%ebx) #explosion ended if the value becomes 0
	je exploded_missile_remove
	jne draw_exploded_missile

draw_exploded_missile:
	pushl %ecx #caller save ecx
	pushl %esi #caller save esi
	pushl %eax #caller save eax
	movb 64(%ebx),%cl
	movl 4(%ebx),%eax
	imull $160,%eax,%eax #80 characters per row * 2 bytes per character * x
	movl 8(%ebx),%esi #esi=y
	imull $2,%esi,%esi #2 bytes per character * x
	addl %esi,%eax
	call mp1_poke #print exploding missile
	popl %eax
	popl %esi
	popl %ecx
	movl (%ebx),%ebx
	jmp explosion_now #check next missile

exploded_missile_remove:
	movl %eax,eax_save # caller save eax
	pushl %ebx
	call mp1_missile_remove
	popl %ebx
	movl %eax,%ebx #ebx=next of deleted pointer
	movl eax_save,%eax
	jmp explosion_now 

moved_off_screen:
	cmpl $0,%ebx #head=NULL
	je Back_from_jump
	cmpl $79,4(%ebx) #head->x > 79
	ja remove_missile_moved_off_screen
	cmpl $24,8(%ebx) # head->y > 24
	ja remove_missile_moved_off_screen
	movl (%ebx),%ebx
	jmp moved_off_screen

remove_missile_moved_off_screen:
	movl %eax,eax_save #caller save eax
	pushl %ebx
	call mp1_missile_remove
	popl %ebx
	movl %eax,%ebx #ebx gets next of deleted pointer
	movl eax_save,%eax
	jmp moved_off_screen

check_exploding:
	movl mp1_missile_list,%esi #head of linked list
	cmpl $0,%esi #head is 0
	je DONE
	movl 28(%esi),%ebx
	cmpl $0,%ebx #exploded!=0 means missile is exploding
	jne NEXT_MISSLE
	je del_missile_from_screen
update_position:
	movl 4(%esi),%ebx 
	movl 12(%esi),%edi
	addl %edi,%ebx
	movl %ebx,4(%esi) # x=x+VX
	movl 8(%esi),%ebx 
	movl 16(%esi),%edi
	addl %edi,%ebx
	movl %ebx,8(%esi) # y=y+vy
	jmp redraw_missile
NEXT_MISSLE:
	movl (%esi),%esi
	jmp check_exploding


del_missile_from_screen:
	jmp update_position


redraw_missile:
	jmp NEXT_MISSLE

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
	movl %edi,%eax #return value is next of deleted pointer
	popl %edi
	popl %esi
	popl %ebx
	leave 
	ret

change_head:
	movl (%esi),%edi #head->next=edi
	movl %edi,mp1_missile_list #new head of linked list
	pushl %esi
	call mp1_free
	popl %esi
	jmp return_missile_remove

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
	movl 8(%ebp),%ebx #command=ebx
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
	jmp remove_crosshairs
update_cross_hair:
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