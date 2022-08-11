;snake game made with the TASM syntax and the original 8086 instruction set
;controls: i - up | j - left | k - down | l - right
IDEAL
MODEL small
STACK 100h
DATASEG
	;constants
	Black equ 0h
	Red equ 0Ch
	Green equ 0Ah
	TileL equ 20d
	KeyboardBufferHead equ 001Ch
	KeyboardBufferTail equ 001Ah

	;variables
	TitleText db "___           _", 0Ah, "         / __|_ _  __ _| |_____", 0Ah, "         \__ \ ` \/ _` | / / -_)", 0Ah, "         |___/_/\_\__,_|_\_\___\", 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, "              Press Any Key$"
	ScoreNumber dw 0FF99h
	ScoreText db '000$'
	Rand dw ?
	FruitPos dw 0508h	;high byte is y-position, low byte is x-position
	HeadPos dw 0508h
	TailPos dw 0508h
	PrevTailPos dw ?
	HeadDirection dw 0h
	TailDirection dw 0h
	Switcher dw 0FF00h, 0FFh, 0100h, 01h	;respresents every direction value: up, left, down, right
	Board db 160 dup(5d)	;represents every tile's state on the screen: 0 - direction change up | 1 - direction change left | 2 - direction change down | 3 - direction change right | 4 - normal part of snake | 5 - empty space
	
CODESEG
;coverts a normal tile position to Board array index, uses the formula P = y*16 + x
;input: cx - tile position | output: ax - Board array index
proc CONVERT_POS

	xor ah, ah
	mov al, ch
	shl al, 4
	adc al, cl
	mov di, ax
	ret

endp CONVERT_POS


;spinlock
;input: si - system timer cycles to wait | output: none
proc DELAY

	xor ah, ah
	int 1Ah
	mov bx, dx
	
delayLoop:
	xor ah, ah
	int 1Ah
	sub dx, bx
	cmp dx, si
	jl delayLoop
	
	ret
	
endp DELAY


;draws a tile of some given color in some given tile position
;input: bl - tile color, cx - tile position | output: none
proc DRAW_TILE
	;convert the tile positions to real positions
	push dx
	push cx
	push di
	xor ah, ah
	mov bh, TileL

	mov al, ch
	mul bh
	mov dx, ax

	mov al, cl
	mul bh
	mov di, ax

	mov al, bl
	mov ah, 0Ch
	xor bh, bh

	;draw a square at the tile position
	mov cx, TileL
row:
	push cx
	mov cx, TileL
line:
	push cx
	mov cx, di
	int 10h

	pop cx
	inc di
	loop line

	pop cx
	inc dx
	sub di, TileL
	loop row

	pop di
	pop cx
	pop dx
	ret

endp DRAW_TILE


;the movement loop responsible for: moving and drawing the snake, checking for colission, displaying the score, halting the code and clearing the keyboard buffer
;input: none | output: none
proc MOVE

	push bx
	push dx
	;scramble the random number based on the current head position
	mov cx, [word ptr HeadPos]
	mov ax, [word ptr Rand]
	add al, cl
	mov [word ptr Rand], ax

	cmp [word ptr HeadDirection], 0h
	jz erase_tail
	cmp dl, dh
	jz erase_tail

add_tile:
	pop dx
	inc dl
	push dx
	jmp skip

erase_tail:
	mov cx, [word ptr TailPos]
	mov [word ptr PrevTailPos], cx
	call CONVERT_POS
	mov al, [byte ptr ds:bp+di]

	cmp al, 3d
	ja no_direction_change
	shl ax, 1
	mov si, ax
	mov dx, [word ptr bx+si]
	mov [word ptr TailDirection], dx
no_direction_change:
	
	mov [byte ptr ds:bp+di], 5d

	;draw a black tile at the tail
	mov bx, Black
	call DRAW_TILE

	mov ax, [word ptr TailDirection]
	add cl, al
	add ch, ah
	mov [word ptr TailPos], cx

skip:
	;update the snake's head position
	mov cx, [word ptr HeadPos]
	mov ax, [HeadDirection]
	add cl, al	;add twice to avoid the sum changing the position
	add ch, ah

	call CONVERT_POS

	;draw a green tile at the new head potision
	mov [word ptr HeadPos], cx
	mov bx, Green
	call DRAW_TILE

	;check if snake hit itself, a wall or a fruit
	cmp cl, 0Fh
	ja lose
	cmp ch, 09h
	ja lose
	cmp [byte ptr ds:bp+di], 5d
	mov [byte ptr ds:bp+di], 4d
	jl lose
	cmp cx, [word ptr FruitPos]
	jz new_fruit
	jmp continue

lose:
	;reset variables to their original values
	mov [ScoreNumber], 0FF99h
	mov [FruitPos], 0508h
	mov [HeadPos], 0508h
	mov [TailPos], 0508h
	mov [HeadDirection], 0
	mov [TailDirection], 0

	lea bx, [Board]
	xor si, si
	mov cx, 160d
reset_board:
	mov [byte ptr bx+si], 5d
	inc si
	loop reset_board

	add sp, 6d	;"clear" the 3 word values from the stack
	jmp setup

new_fruit:
	mov cx, 3d
new_fruit_loop:
	;reduce Rand to range 0-159 with AND masking
	xor di, di
	mov bx, [word ptr Rand]
	mov ax, bx
	and ax, 127d
	add di, ax
	add bl, bh
	
	mov ax, bx
	and ax, 31d
	add di, ax
	add bl, bh
	
	mov ax, bx
	and ax, 1d
	add di, ax

	;check if the random fruit spawned inside the snake
	cmp [byte ptr ds:bp+di], 4d
	ja use_random
	rol [word ptr Rand], 1
	loop new_fruit_loop
	
	mov cx, [PrevTailPos]	;generate the fruit at the snake's previous tail position
	jmp finally

use_random:
	mov ax, di
	mov cx, di
	shr ax, 4d
	mov ch, al
	shl al, 4d
	sub cl, al

finally:
	mov [word ptr FruitPos], cx
	mov bx, Red
	call DRAW_TILE

	;increase the size of the snake
	pop dx
	inc dh
	push dx

	;increase the score
	mov ax, [word ptr ScoreNumber]
	clc		;prevent a carry from before
	inc ax
	daa		;adjust ax to BCD after addition
	adc ah, 0h	;increase ah by 1 if lower byte overflowed
	mov [word ptr ScoreNumber], ax
	
	;adjust the score number to ASCII text
	lea bx, [ScoreText]
	mov dh, ah
	mov ah, al
	and ah, 0Fh	;mask the first 4 bits
	shr al, 04h
	or ax, 3030h
	mov [word ptr bx+1], ax

	mov ah, dh
	and ah, 0Fh	;mask the first 4 bits
	or ah, 30h
	mov [byte ptr bx], ah

continue:

	;set cursor in order to print the score
	xor bh, bh
	mov dx, 013h
	mov ah, 02h
	int 10h

	;print the score to standard ouput
	mov ah, 09h
	lea dx, [ScoreText]
	int 21h

	;clears the keyboard buffer (if the player pressed too many buttons)
	push 0040h
	pop es
   	mov ax, [es:KeyboardBufferTail]
   	mov [es:KeyboardBufferHead], ax

	;wait some time for the player to press a key
	mov si, 04h
	call DELAY

	pop dx
	pop bx
	ret

endp MOVE


start:
	mov ax, @data
	mov ds, ax

	mov ax, 13h
	int 10h

	xor bh, bh
	mov dx, 060Ah
	mov ah, 02h
	int 10h

	mov ah, 09h
	lea dx, [TitleText]
	int 21h
	
	xor ah, ah
	int 16h

setup:
	;clear the screen
	mov ax, 13h
	int 10h

	;set random seed
	xor ah, ah
	int 1Ah
	mov [word ptr Rand], dx

	;set up variables
	lea bp, [Board]
	lea bx, [Switcher]
	mov dx, 0201h	;low byte is current size of snake, high byte is max size of snake

until_press:
	call MOVE

movement_skip:
	mov ah, 1h
	int 16h		;sets the zero flag if a key was pressed and puts the character's ASCII value into al
	jz until_press

check_keypress:

	xor ah, ah	
	;check if the character is in the array bound
	sub ax, 69h		;instead of comparing twice
	cmp ax, 3h
	ja until_press

	;check if wanted direction is not on the same axis as current direction
	shl ax, 1
	mov si, ax
	mov ax, [word ptr bx+si]
	test ax, [word ptr HeadDirection]	;if ax AND HeadDirection != 0, the player tried to go to a direction on the same aixs
	jnz until_press
	mov [word ptr HeadDirection], ax

	;put a mark of direction change at the head's position
	mov cx, [word ptr HeadPos]
	call CONVERT_POS
	mov ax, si
	shr ax, 1
	mov [byte ptr ds:bp+di], al
	jmp until_press

exit:
	mov ax, 4c00h
	int 21h
END start