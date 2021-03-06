//
//  client.mm
//  Created by Allan Odgaard on 2007-09-22.
//

#include <sys/uio.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/select.h>
#include <stdarg.h>
#include <sys/stat.h>
#include <map>
#include <vector>
#include <string.h>
#include <poll.h>
#include <stdlib.h>

#import <Foundation/Foundation.h>
#import "Dialog2.h"

static double const AppVersion  = 2.0;
static size_t const AppRevision = APP_REVISION;

id connect ()
{
	NSString* portName = DialogServerConnectionName;
	if(char const* var = getenv("DIALOG_PORT_NAME"))
		portName = [NSString stringWithUTF8String:var];

	id proxy = [NSConnection rootProxyForConnectionWithRegisteredName:portName host:nil];
	[proxy setProtocolForProxy:@protocol(DialogServerProtocol)];
	return proxy;
}

char const* create_pipe (char const* name)
{
	char* filename;
	asprintf(&filename, "%s/dialog_fifo_%d_%s", getenv("TMPDIR") ?: "/tmp", getpid(), name);
	int res = mkfifo(filename, 0666);
	if((res == -1) && (errno != EEXIST))
	{
		perror("Error creating the named pipe");
		exit(1);
   }
	return filename;
}

int open_pipe (char const* name, int oflag)
{
	int fd = open(name, oflag);
	if(fd == -1)
	{
		perror("Error opening the named pipe");
		exit(1);
	}
	return fd;
}

int main (int argc, char const* argv[])
{
	if(argc == 2 && strcmp(argv[1], "--version") == 0)
	{
		fprintf(stderr, "%1$s %2$.1f (" COMPILE_DATE " revision %3$zu)\n", getprogname(), AppVersion, AppRevision);
		return 0;
	}

	// If the argument list starts with a switch then assume it’s meant for trunk dialog
	// and pass it off
	if(argc > 1 && *argv[1] == '-')
		execv(getenv("DIALOG_1"), (char* const*)argv);

	NSAutoreleasePool* pool = [NSAutoreleasePool new];
	id<DialogServerProtocol> proxy = connect();
	if(!proxy)
	{
		fprintf(stderr, "error reaching server\n");
		exit(1);
	}

	char const* stdin_name  = create_pipe("stdin");
	char const* stdout_name = create_pipe("stdout");
	char const* stderr_name = create_pipe("stderr");

	NSMutableArray* args = [NSMutableArray array];
	for(size_t i = 0; i < argc; ++i)
		[args addObject:[NSString stringWithUTF8String:argv[i]]];

	NSDictionary* dict = [NSDictionary dictionaryWithObjectsAndKeys:
		[NSString stringWithUTF8String:stdin_name],			@"stdin",
		[NSString stringWithUTF8String:stdout_name],			@"stdout",
		[NSString stringWithUTF8String:stderr_name],			@"stderr",
		[NSString stringWithUTF8String:getcwd(NULL, 0)],	@"cwd",
		[[NSProcessInfo processInfo] environment],			@"environment",
		args,																@"arguments",
		nil
	];

	[proxy connectFromClientWithOptions:dict];

	int stdin_fd  = open_pipe(stdin_name, O_WRONLY);
	int stdout_fd = open_pipe(stdout_name, O_RDONLY);
	int stderr_fd = open_pipe(stderr_name, O_RDONLY);

	std::map<int, int> fd_map;
	fd_map[STDIN_FILENO] = stdin_fd;
	fd_map[stdout_fd]    = STDOUT_FILENO;
	fd_map[stderr_fd]    = STDERR_FILENO;

	if(isatty(STDIN_FILENO) != 0)
	{
		fd_map.erase(fd_map.find(STDIN_FILENO));
		close(stdin_fd);
	}

	while(fd_map.size() > 1 || (fd_map.size() == 1 && fd_map.find(STDIN_FILENO) == fd_map.end()))
	{
		fd_set readfds, writefds;
		FD_ZERO(&readfds); FD_ZERO(&writefds);

		int num_fds = 0;
		for(auto const& pair : fd_map)
		{
			FD_SET(pair.first, &readfds);
			num_fds = std::max(num_fds, pair.first + 1);
		}

		int i = select(num_fds, &readfds, &writefds, NULL, NULL);
		if(i == -1)
		{
			perror("Error from select");
			continue;
		}

		std::vector<int> to_remove;
		for(auto const& pair : fd_map)
		{
			if(FD_ISSET(pair.first, &readfds))
			{
				char buf[1024];
				ssize_t len = read(pair.first, buf, sizeof(buf));

				if(len == 0)
						to_remove.push_back(pair.first); // we can’t remove as long as we need the iterator for the ++
				else	write(pair.second, buf, len);
			}
		}

		for(int key : to_remove)
		{
			if(fd_map[key] == stdin_fd)
				close(stdin_fd);
			fd_map.erase(key);
		}
	}

	close(stdout_fd);
	close(stderr_fd);
	unlink(stdin_name);
	unlink(stdout_name);
	unlink(stderr_name);

	[pool release];
	return 0;
}