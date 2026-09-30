/* Launcher for the scheduled backup. launchd starts this binary, which runs the
 * macbackup script in a child process. Full Disk Access granted to this binary
 * therefore covers the backup, without granting it to /bin/bash in general. */
#include <spawn.h>
#include <stdio.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: macbackup-agent <script> [args...]\n");
    return 2;
  }
  char *args[argc + 1];
  args[0] = "/bin/bash";
  for (int i = 1; i < argc; i++) args[i] = argv[i];
  args[argc] = NULL;

  pid_t pid;
  int status;
  if (posix_spawn(&pid, "/bin/bash", NULL, NULL, args, environ) != 0) {
    perror("posix_spawn");
    return 1;
  }
  if (waitpid(pid, &status, 0) < 0) {
    perror("waitpid");
    return 1;
  }
  return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}
