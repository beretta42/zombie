all: zombie


bounce.h: bounce.s
	lwasm -f raw -o bounce bounce.s
	xxd -i bounce > bounce.h

zombie: zombie.c bounce.h
	gcc -o zombie zombie.c -ledit

clean:
	rm -f *~ zombie bounce bounce.h
