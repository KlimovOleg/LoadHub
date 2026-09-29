<?php

declare(strict_types=1);

use Illuminate\Support\Facades\DB;

// Страховка от ловушки «тесты стёрли рабочую базу»: RefreshDatabase
// не должен никогда запускаться на loadhub.
it('runs tests against the dedicated MariaDB test database', function (): void {
    expect(DB::connection()->getDriverName())->toBe('mariadb')
        ->and(DB::connection()->getDatabaseName())->toStartWith('loadhub_testing');
});
