<?php

declare(strict_types=1);

it('responds on the health check endpoint', function (): void {
    $this->get('/up')->assertOk();
});

it('rejects unauthenticated api requests with json 401', function (): void {
    $this->getJson('/api/user')->assertUnauthorized();
});
