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
crosshairs_y:		.long 0x0	# X-position of the crosshairs
crosshairs_x:		.long 0x0	# Y-position of the crosshairs

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
	movl mp1_missile_list,%ebx
	jmp check_exploding
DONE:
	jmp moved_off_screen
Back_from_jump:
	jmp explosion_now
Back_from_explosions:
	movl $0,%ecx
	movl $3844,%esi #[24*160+18*2]-32 because 32 is being added to start of loop
	jmp redraw_bases
Back_from_redraw_bases:
	jmp redraw_crosshairs

redraw_bases:
	cmpl $3,%ecx
	je Back_from_redraw_bases
	addl $32,%esi #2*16 is the next location for base
	movl $base_alive,%ebx
	addl %ecx,%ebx
	cmpb $0,1(%ebx)
	je dead_base
	movl $base_pic,%edi
	jmp draw_base
dead_base:
	movl $dead_base_pic,%edi
	jmp draw_base

draw_base:
	pushl %ecx
	pushl %eax
	pushl %edi
	movb (%edi),%cl
	movl %esi,%eax
	pushl %eax
	call mp1_poke
	popl %eax
	addl $2,%esi
	movl %esi,%eax
	movb  1(%edi),%cl
    pushl %eax
	call mp1_poke
	popl %eax
	addl $2,%esi
	movl %esi,%eax
	movb  2(%edi),%cl
	pushl %eax
	call mp1_poke
	popl %eax
	addl $2,%esi
	movl %esi,%eax
	movb  3(%edi),%cl
	pushl %eax
	call mp1_poke
	popl %eax
	addl $2,%esi
	movl %esi,%eax
	movb  4(%edi),%cl
	pushl %eax
	call mp1_poke
	popl %eax
	popl %edi
	popl %eax
	popl %ecx
	incl %ecx
	jmp redraw_bases

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
	movb EXPLOSION(%ebx),%cl
	movl X(%ebx),%eax
	imull $160,%eax,%eax #80 characters per row * 2 bytes per character * x
	movl Y(%ebx),%esi #esi=y
	imull $2,%esi,%esi #2 bytes per character * x
	addl %esi,%eax
	call mp1_poke #print exploding missile
	popl %eax
	popl %esi
	popl %ecx
	movl (%ebx),%ebx
	jmp explosion_now #check next missile

exploded_missile_remove:
	pushl %eax # caller save eax
	pushl %ebx
	call mp1_missile_remove
	popl %ebx
	movl %eax,%ebx #ebx=next of deleted pointer
	popl %eax
	jmp explosion_now 

moved_off_screen:
	cmpl $0,%ebx #head=NULL
	je Back_from_jump
	cmpl $79,4(%ebx) #head->x > 79
	ja remove_missile_moved_off_screen
	cmpl $24,8(%ebx) # head->y > 24
	ja remove_missile_moved_off_screen
	jmp redraw_missile

redraw_missile:
	pushl %eax
	pushl %esi
	pushl %ecx
	movl Y(%ebx),%esi 
	imull $160,%esi,%eax # 80*2*crosshairs_y=eax
	movl X(%ebx),%esi # esi=crosshairs_x
	imul $2,%esi 
	addl %esi,%eax # eax=eax+2*crosshairs_x
	movb $43,%cl #print hash for crosshairs
	pushl %edx
	call mp1_poke
	popl %edx
	popl %ecx
	popl %esi
	popl %eax
	movl (%ebx),%ebx
	jmp moved_off_screen

remove_missile_moved_off_screen:
	pushl %eax #caller save eax
	pushl %ebx
	call mp1_missile_remove
	popl %ebx
	movl %eax,%ebx #ebx gets next of deleted pointer
	popl %eax
	jmp moved_off_screen

mp1_missile_remove: # void* remove(void* ptr) returns pointer to next of deleted pointer
	pushl %ebp
	movl  %esp,%ebp
	pushl %ebx
	pushl %esi
	pushl %edi
	movl 8(%ebp),%ebx # ebx= pointer of missile to remove
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


check_exploding:
	cmpl $0,%ebx #head is 0
	je DONE
	movl EXPLODED(%ebx),%esi
	cmpl $0,%esi #exploded!=0 means missile is exploding
	jne NEXT_MISSLE
	je update_position

NEXT_MISSLE:
	movl (%ebx),%ebx
	jmp check_exploding

update_position:
	#pushl %eax
	#pushl %esi
	#pushl %ecx
	#movl Y(%ebx),%esi
	#imull $160,%esi,%eax
	#movl X(%ebx),%esi
	#imull $2,%esi
	#addl %esi,%eax
	#movb $32,%cl
	#cmpl $4160,%eax #TEMPORARY FOR STOPPING SEGFAULT
	#jg NEXT_MISSLE
	#call mp1_poke #print " " for original missile
	#popl %ecx
	#popl %esi
	#popl %eax
	movl X(%ebx),%esi 
	movl VX(%ebx),%edi
	addl %edi,%esi
	movl %esi,X(%ebx) # x=x+VX
	movl Y(%ebx),%esi 
	movl VY(%ebx),%edi
	addl %edi,%esi
	movl %esi,Y(%ebx) # y=y+vy
	jmp NEXT_MISSLE


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
	movl crosshairs_y,%esi 
	imull $160,%esi,%eax # 80*2*crosshairs_y=eax
	movl crosshairs_x,%esi # esi=crosshairs_x

	imull $2,%esi 
	addl %esi,%eax # eax=eax+2*crosshairs_x

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
	movl $0,%eax
	jmp RETURN_NOW

# ----------------- Functions private to this file -------------------

update_missiles:
		jmp RETURN_NOW

mp1_ioctl_startgame:
    movl $12,crosshairs_y
	movl $40,crosshairs_x
	movl $base_alive,%ebx
	movb $1,1(%ebx) # first base is alive
	movb $1,2(%ebx) # second base is alive
	movb $1,3(%ebx) # third base is alive
	jmp RETURN_NOW

mp1_ioctl_addmissile:
	movl 8(%ebp),%ebx #ebx=argument
	pushl $36 #36 bit memory needs to be freed
	call mp1_malloc 
	popl %edi #edi=36
	cmpl $0,%eax #returnptr is 0
	je RET_INVALID
	shrl $16,X(%ebx)
	shrl $16,Y(%ebx)
	pushl %edi #push36
	pushl %ebx #pushptr with argument to be copied
	pushl %eax # pushptr to kernel space created
	call mp1_copy_to_user
	cmpl $0,%eax #all memory allocated
	popl %eax
	popl %ebx
	popl %edi
	je add_to_linked_list
	pushl %eax #free from memory when space not found
	call mp1_free
	popl %eax
	jmp RET_INVALID

add_to_linked_list:
	movl mp1_missile_list,%edi #head=edi
	movl %edi,(%eax) # eax->next=head
	movl %eax,mp1_missile_list #eax becomes new head
	jmp RET_ZERO #return 0 

mp1_ioctl_movexhairs:
	jmp remove_crosshairs
update_cross_hair:
	movw 10(%ebp),%bx #lower 16 bits of argument
	movw 8(%ebp),%si #upper 16 bits of argument
	movl crosshairs_y,%edi # current crosshairs_y
	addw %bx,%di #add lower 16 bits to crosshairs_y
	cmpl $25,%edi #compare to 25
	jb VALID_X #move ahead if valid
	subw %bx,%di #subtract again if invalid
VALID_X: 
	movl %edi,crosshairs_y #update crosshairs_y
	movl crosshairs_x,%edi 
	addw %si,%di #update crosshairs_x
	cmpl $80,%edi #compare to 80
	jb VALID_Y
	subw %si,%di #subtract again if invalid
VALID_Y:
	movl %edi,crosshairs_x

	jmp RET_ZERO

mp1_ioctl_getstatus:
		jmp RETURN_NOW

mp1_ioctl_endgame:
		movl mp1_missile_list,%ebx #head=ebx
		cmpl $0,%ebx # head==0 return
		je RETURN_NOW
		movl (%ebx),%esi #esi=head->next
		pushl %ebx #free head
		call mp1_free
		popl %ebx
		movl %esi,mp1_missile_list #head=head->next
		jmp mp1_ioctl_endgame


jmptable:
	.long mp1_ioctl_startgame,mp1_ioctl_addmissile,mp1_ioctl_movexhairs,mp1_ioctl_getstatus,mp1_ioctl_endgame

remove_crosshairs:
	pushl %eax
	pushl %esi
	pushl %ecx
	movl crosshairs_y,%esi
	imull $160,%esi,%eax
	movl crosshairs_x,%esi
	imull $2,%esi
	addl %esi,%eax
	movb $32,%cl
	call mp1_poke #print " " for original crosshairs
	popl %ecx
	popl %esi
	popl %eax
	jmp update_cross_hair
