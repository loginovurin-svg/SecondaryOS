/*
 * stub_proot.c — минимальная заглушка proot (ELF aarch64)
 * Имитирует поведение proot: парсит аргументы -r, -b, находит команду
 * и выполняет её через system(). Используется для тестирования до
 * установки настоящего proot.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>

int main(int argc, char *argv[]) {
    char *root_dir = NULL;
    char full_cmd[4096] = {0};
    int cmd_started = 0;

    // Парсим аргументы как настоящий proot
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-r") == 0 && i + 1 < argc) {
            root_dir = argv[i + 1];
            i++;
        } else if (strcmp(argv[i], "-b") == 0) {
            i++; // пропускаем bind-путь
        } else if (strcmp(argv[i], "-c") == 0 && i + 1 < argc) {
            // Всё после -c — это команда для /bin/sh
            for (int j = i + 1; j < argc; j++) {
                if (cmd_started) strcat(full_cmd, " ");
                strcat(full_cmd, argv[j]);
                cmd_started = 1;
            }
            break;
        }
    }

    printf("stub_proot: root=%s\n", root_dir ? root_dir : "(null)");
    printf("stub_proot: command=%s\n", full_cmd);

    if (strlen(full_cmd) > 0) {
        int ret = system(full_cmd);
        int exit_code = WEXITSTATUS(ret);
        printf("stub_proot: exited with code %d\n", exit_code);
        return exit_code;
    }

    printf("stub_proot: no command, exiting 0\n");
    return 0;
}
