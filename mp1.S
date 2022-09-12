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

	pushl mp1_missile_list
	call update_missiles
	popl %ebx

	movl $0,%ecx #initialise ecx register
	movl $3844,%esi #[24*160+18*2]-32 because 32 is being added to start of loop
	jmp redraw_bases
Back_from_redraw_bases:

	jmp redraw_crosshairs

redraw_bases:
	cmpl $3,%ecx #loop goes on for 3 iterations for 3 bases
	je Back_from_redraw_bases
	addl $32,%esi #2*16 is the next location for base
	movl $base_alive,%ebx
	addl %ecx,%ebx
	cmpb $0,(%ebx) # check if basealive[0]=0
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
	addl $2,%esi #every block is two bytes
	movl %esi,%eax
	movb  1(%edi),%cl #every character is a byte
    pushl %eax
	call mp1_poke
	popl %eax
	addl $2,%esi #every block is two bytes
	movl %esi,%eax
	movb  2(%edi),%cl #every character is a byte
	pushl %eax
	call mp1_poke
	popl %eax
	addl $2,%esi #every block is two bytes
	movl %esi,%eax
	movb  3(%edi),%cl #every character is a byte
	pushl %eax
	call mp1_poke
	popl %eax
	addl $2,%esi #every block is two bytes
	movl %esi,%eax
	movb  4(%edi),%cl #every character is a byte
	pushl %eax
	call mp1_poke
	popl %eax
	popl %edi
	popl %eax
	popl %ecx
	incl %ecx
	jmp redraw_bases


mp1_missile_remove: # void* remove(void* ptr) returns pointer to next of deleted pointer
	pushl %ebp
	movl  %esp,%ebp
	pushl %ebx
	pushl %esi
	pushl %edi
	movl 8(%ebp),%ebx # ebx= pointer of missile to remove (argument of function)
	cmpl $0,%ebx
	je RETURN_NOW
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
	movl %edi,(%esi) # prev->next=temp
	pushl %ebx
	call mp1_free
	popl %ebx
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
	movl %edi,%eax #return value is next of deleted pointer
	popl %edi
	popl %esi
	popl %ebx
	leave 
	ret


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
	cmpl $0,%ebx #command<0 or command>4
	jl RET_INVALID 
	cmpl $4,%ebx
	ja RET_INVALID
	jmp *jmptable(,%ebx,4)

RET_INVALID:
	movl $-1,%eax #return value is -1
	jmp RETURN_NOW

RETURN_NOW:
		popl %edi #common callee teardown
		popl %esi
		popl %ebx
		leave 	
		ret

RET_ZERO:
	movl $0,%eax #return value is 0
	jmp RETURN_NOW

# ----------------- Functions private to this file -------------------

update_missiles:
	pushl %ebp
	movl %esp,%ebp
	pushl %ebx
	pushl %esi
	pushl %edi #push all elements

	movl 8(%ebp),%esi #esi is ptr to the missile to be updated
update_missile_loop:
	cmpl $0,%esi #head is null
	je RETURN_NOW #end of linked list reached
	movl (%esi),%edi
	cmpl $0,EXPLODED(%esi) #exploded is 0 means not exploding
	#movl %esi,debug_value
	je not_exploding

	pushl %edi
	pushl %esi
	call missile_is_exploding # returns updated esi value
	popl %esi
	popl %edi

	movl %edi,%esi
	jmp update_missile_loop

missile_is_exploding:
	pushl %ebp
	movl %esp,%ebp
	pushl %ebx
	pushl %edi
	pushl %esi

	movl 8(%ebp),%esi #esi gets argument passed to function

	pushl %esi
	call missile_explode
	popl %esi

	cmpl $0,%eax #when missile explode returns not 0 notify user
	jne notify_user
back_from_notification:

	decl EXPLODED(%esi) #decrement exploded
	cmpl $0,EXPLODED(%esi) #check if becomes 0 meaning done exploding
	jne draw_exploded_missile

	pushl $32
	pushl %esi
	call redraw_missile #erased missile at esi by drawing " "
	popl %esi
	popl %ebx

	pushl %esi
	call mp1_missile_remove
	popl %esi

	jmp RETURN_NOW

notify_user:

	call mp1_notify_user

	jmp back_from_notification

draw_exploded_missile:
	pushl $64
	pushl %esi
	call redraw_missile #draw exploded missile at esi by drawing "@"
	popl %esi
	popl %edi
	jmp RETURN_NOW

not_exploding:
	pushl %edi

    pushl %esi

	pushl $32
	pushl %esi
	call redraw_missile #erased missile at esi by drawing " "
	popl %esi
	popl %ebx

	movl X(%esi),%ebx #x=ebx
	movl VX(%esi),%edi #edi=VX
	addl %edi,%ebx #x=x+VX
	movl %ebx,X(%esi) # x=x+VX in struct
	movl Y(%esi),%ebx #y=ebx
	movl VY(%esi),%edi #edi=vy
	addl %edi,%ebx #y=y+vy
	movl %ebx,Y(%esi) # y=y+vy in struct

	popl %esi

	cmpw $79,6(%esi) #head->x > 79 || x<0
	ja remove_missile_moved_off_screen
	cmpw $24,10(%esi) # head->y > 24
	ja remove_missile_moved_off_screen

	jmp check_dest_reached

check_dest_reached:
	movl X(%esi),%edi
	shrl $16,%edi #shift right for top 16 bits
	#movw X+2(%esi),%di # edi=X
	cmpl DEST_X(%esi),%edi #when x is same as dest x check y value
	je check_y

	pushl C(%esi)
	pushl %esi
	call redraw_missile #redraw missile if dest not reached
	popl %esi
	popl %edi
	#movl (%esi),%esi # next pointer to be checked

	popl %edi
	movl %edi,%esi
	jmp update_missile_loop

check_y:
    movl Y(%esi),%edi #edi=Y
	shrl $16,%edi #shift right for top 16 bits
	cmpl DEST_Y(%esi),%edi #when y=DEST_Y start exploding
	je at_dest 

	pushl C(%esi) #value to be printed for missile
	pushl %esi
	call redraw_missile #erased missile at esi by drawing " "
	popl %esi
	popl %edi

	popl %edi
	movl %edi,%esi
	jmp update_missile_loop

at_dest:

	pushl %esi
	call missile_is_exploding
	popl %esi

	popl %edi
	movl %edi,%esi
	jmp update_missile_loop

remove_missile_moved_off_screen:

	pushl %esi
	call mp1_missile_remove
	popl %esi

	popl %edi
	movl %edi,%esi
	jmp update_missile_loop

redraw_missile:
	pushl %ebp
	movl %esp,%ebp
	pushl %ebx
	pushl %esi
	pushl %edi

	movl 8(%ebp),%ebx #argument of redraw missile which is ptr to struct
	cmpl $0,%ebx
	je RETURN_NOW
	movl X(%ebx),%esi #esi=X
	movl Y(%ebx),%edi #edi=Y
	shrl $16,%esi #shift right for top 16 bits
	shrl $16,%edi  #shift right for top 16 bits
	imull $160,%edi,%eax # 80*2*y=eax
	imull $2,%esi  #X*2
	addl %esi,%eax # eax=eax+2*X
	movb 12(%ebp),%cl #print g for missile

	pushl %edx
	call mp1_poke
	popl %edx

	popl %edi
	popl %esi
	popl %ebx
	leave 
	ret
mp1_ioctl_startgame:
    movl $12,crosshairs_y #centre of screen
	movl $40,crosshairs_x #centre of screen
	movl $base_alive,%ebx
	movb $1,(%ebx) # first base is alive
	movb $1,1(%ebx) # second base is alive
	movb $1,2(%ebx) # third base is alive
	jmp RETURN_NOW

mp1_ioctl_addmissile:
	movl 8(%ebp),%ebx #ebx=argument

	pushl $36 #36 bit memory needs to be freed
	call mp1_malloc 
	popl %edi #edi=36

	cmpl $0,%eax #returnptr is 0
	je RET_INVALID
	pushl %edi #push36
	pushl %ebx #pushptr with argument to be copied
	pushl %eax # pushptr to kernel space created
	call mp1_copy_from_user
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
		movl $base_alive,%esi
		andl $0,%edi #initialize edi with 0
		movw mp1_score,%di
		cmpb $0,(%esi) #compare 0 with base alive[0]
		jne base_1_alive



	base_2_check:
		cmpb $0,1(%esi) #compare 0 with base alive[1]
		jne base_2_alive
	base_3_check:
	    cmpb $0,2(%esi) #compare 0 with base alive[2]
		jne base_3_alive
	base_check_done:
		pushl %edi
		movl %esp,%ecx
		pushl $4 #4 bytes to be copied 
		pushl %ecx
		pushl 8(%ebp) #argument
		call mp1_copy_to_user
		addl $12,%esp #pop from stack
		cmpl $0,%eax
		popl %edi
		jne RET_INVALID
		jmp RET_ZERO

base_1_alive:
		orl $0x10000,%edi #hex value for 2^16 for 16th bit
		jmp base_2_check
base_2_alive:
		orl $0x20000,%edi #hex value for 2^17 for 17th bit
		jmp base_3_check
base_3_alive:
		orl $0x40000,%edi #hex value for 2^18 for 18th bit
		jmp base_check_done


mp1_ioctl_endgame:
		movl mp1_missile_list,%ebx #head=ebx
		cmpl $0,%ebx # head=null then return
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
	imull $160,%esi,%eax #160*y+2*x=offset for screen printing
	movl crosshairs_x,%esi
	imull $2,%esi
	addl %esi,%eax
	movb $32,%cl
	call mp1_poke #print " " for original crosshairs

	popl %ecx
	popl %esi
	popl %eax
	jmp update_cross_hair


mp1_ptr_to_user:
	.long 0x0

