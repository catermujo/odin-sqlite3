#include "sqlite3.h"

#include <stdio.h>

static int check_count(void *context, int columns, char **values, char **names) {
    (void)columns;
    (void)names;
    *(int *)context = values[0] && values[0][0] == '1' && values[0][1] == '\0';
    return 0;
}

int main(void) {
    sqlite3 *database = NULL;
    char *error = NULL;
    int matched = 0;
    if (sqlite3_libversion_number() != 3045001) return 9;
    if (!sqlite3_compileoption_used("ENABLE_RTREE")) return 10;
    if (sqlite3_open(":memory:", &database) != SQLITE_OK) return 11;
    if (sqlite3_exec(database,
                     "CREATE VIRTUAL TABLE boxes USING rtree(id,min_x,max_x,min_y,max_y);"
                     "INSERT INTO boxes VALUES(1,0,10,0,10),(2,20,30,20,30);"
                     "SELECT count(*) FROM boxes WHERE min_x<=5 AND max_x>=5 AND min_y<=5 AND max_y>=5;",
                     check_count, &matched, &error) != SQLITE_OK) {
        fprintf(stderr, "%s\n", error ? error : "RTree query failed");
        sqlite3_free(error);
        sqlite3_close(database);
        return 12;
    }
    sqlite3_close(database);
    if (!matched) return 13;
    puts("version=3045001 ENABLE_RTREE=1 query_count=1");
    return 0;
}
