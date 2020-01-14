; Capacity sensor, ATtiny85
; Clock 8mHz
; Antenna - PB3 
; Charge electrode - PB2 (connect to the ground ot body)
; PWM output - PB0

.include "tn85def.inc" 

.def rMP1 = r16				; Multi-purpose register 1 = r16
.def rMP2 = r17				; Multi-purpose register 2 = r17
.def rSUM = r6				; Register to save sum = r6
.def rCOUNTER = r5			; Counter register = r5

rjmp init				; Start from init



; ========== INIT ==========
init:
	; Reset rSUM to 10 == number of readings
	ldi rMP1, 10		
	mov rCOUNTER, rMP1	
	; Clear sum register
	clr rSUM		
	
	cli				; Disable interrupts
	sbi DDRB, DDB0			; Set OC0A as output
	sbi DDRB, DDB2			; Set PB2 as output
	
	; Setup Timer 0
	; Fast PWM mode, output A low at cycle start
	ldi rMP1, (1<<COM0A1)|(1<<COM0A0)|(1<<WGM01)|(1<<WGM00)
	out TCCR0A, rMP1		; To timer control register A
	
	; Set Timer 0 Prescaler = 1
	ldi rMP1, 1<<CS00 
	out TCCR0B, rMP1		; To timer control register B
	
	; PWM compare value 
	ldi rMP1,0			; Start from 0% intensity
	out OCR0A,rMP1			; To compare match register A
	sei				; Enable interrupts
	rjmp loop			; To main loop



; ========== LOOP ==========
loop:	
	; Read antenna capacitance
	; Calculate average value reading capacitance several times, 
	rcall readCap			; Capacitance value saved to rMP1
	add rSUM, rMP1			; rSUM += capValue
	brcc repeatReadCap		; If it does not overflows, go to repeatReadCap label (repeat reading)
	; If it overflows, set r6 to 255 (max value)
	clr rSUM				
	dec rSUM				
	rjmp updatePWM			; Skip and go to updatePWM label

repeatReadCap:
	dec rCOUNTER			; r5 is counting down the number of readings we've made
	brne loop			; If r5 != 0, go to label loop (one more reading)
					; Else, update PWM value
updatePWM:
	; Reset rSUM to 10 == number of readings
	ldi rMP1, 10		
	mov rCOUNTER, rMP1	
	
	lsr rSUM			; Divide sum by two and set volume level 
	out OCR0A,r6			; to compare match register A
	clr rSUM			; Clear sum value

rjmp loop				; Go to loop begin



; ========== CAPACITANCE READING ==========
.equ chargePin = 2
.equ antennaPin = 3
readCap:
	; Setup ADC:
	; Vcc as Aref (default)
	; Left adjust
	; Read from PB3
	ldi rMP1, (1<<ADLAR|1<<MUX1|1<<MUX0)
	out ADMUX, rMP1

	; Start reading capacitance
	cbi PORTB, antennaPin		; Ground antenna pin				
	cbi PORTB, chargePin		; Ground charge pin
	ldi rMP1, 0b00011111		; Prepare value for DDRB 
	out DDRB, rMP1			; Set all port as output, load value
	rcall wait			; Wait a bit for pin mode changing
	cbi DDRB, antennaPin		; Set antenna pin as high-impedance input
	rcall wait			; Wait a bit for pin mode changing
	cli				; Disable interrupts (timing critical)
	sbi PORTB, chargePin		; Set charge pin to high
	rcall waitForCharge		; Wait a specific amount of time
	rcall readADC			; Start reading 

	ret				; Return, value saved to rMP1



; ========== WAIT PROCEDURES ===========
; Simple wait for port mode changing
wait:
	ldi rMP2, 10				; Set counter value to 10
waitL:
	dec rMP2				; Decrease counter
	brne waitL				; If counter != 0, go to waitL label
	ret					; Else return

; Wait for capacitance changing
waitForCharge:					
	ldi rMP2,8				; Set counter value to 8 (the value obtained by experiments)
waitForChargeL:				
	nop	
	nop
	dec rMP2				; Decrease counter
	brne waitForChargeL			; If counter != 0, go to waitForChargeL label
	ret					; Else return



; ========== ADC READING ============
readADC:
	; Enable ADC
	; Begin conversion cycle
	; Clear interrupt flag
	; Set division factor to 16
	ldi rMP1, (1<<ADEN|1<<ADSC|1<<ADIF|1<<ADPS2)
	out ADCSRA, rMP1
	sei				; Enable interrupts
waitForConversion:
	sbis ADCSRA, ADIF		; If conversion finished, skip the next command
	rjmp waitForConversion		; Wait for conversion, go to waitForConversion label
	in rMP2, ADCL			; Read low ADC byte to rMP2
	in rMP1, ADCH			; Read high ADC byte to rMP1
	sbrc rMP2, 7			; If low byte >= 128, skip the next command 
	inc rMP1			; Else increase rMP1 value
	ret				; Return, capacitance value saved to rMP1

