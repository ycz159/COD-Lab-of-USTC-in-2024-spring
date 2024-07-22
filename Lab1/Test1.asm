.text
Fibonacci: 
	addi x2,x0,5
	li t1,1
	li t2,1
	li s1,0
	li s2,0
	addi t5,x2,-2
	add t4,x2,x0
	bge x0,t5,exit1
loop1:
	addi t5,t4,-2
	bge x0,t5,exit2
	
	#add t5,t2,x0
	add t3,t2,x0
	add s3,s2,x0
	#add t2,t1,t2
	add t2,t2,t1
	add s2,s2,s1
	bgeu t2,t1,jump1
	addi s2,s2,1
	#add t1,t5,x0
jump1:	add t1,t3,x0
	add s1,s3,x0
	
	addi t4,t4,-1
	and t5,,t5,x0
	beq t5,x0,loop1
	
exit1:	
	addi x3,x0,0
	addi x4,x0,1
	and t5,t5,x0
	beq t5,x0,exit
exit2:	
	add x3,x0,s2
	add x4,x0,t2
	and t5,t5,x0
	beq t5,x0,exit
exit:	
	ebreak
