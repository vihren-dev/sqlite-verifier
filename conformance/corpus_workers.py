"""Run complete shard validators while preserving input-order failure precedence."""

from collections.abc import Iterable, Iterator
from concurrent.futures import Executor, Future

from conformance.case_format import Json


def validated_shards(payloads: Iterable[tuple[bytes, dict[str, Json]]],
                     executor: Executor | None = None) -> Iterator[list[dict[str, Json]]]:
    """Retain the serial primitive or submit independent payloads to a caller-owned executor.

    Read-ahead failures wait behind earlier payload results. The caller then
    applies global name and binding checks before consuming the next result.
    """
    from conformance.corpus_shards import payload_records

    if executor is None:
        for payload, binding in payloads:
            yield payload_records(payload, binding)
        return
    pending: list[Future[list[dict[str, Json]]] | Exception] = []
    try:
        for payload, binding in payloads:
            pending.append(executor.submit(payload_records, payload, binding))
    except Exception as error:
        pending.append(error)
    for result in pending:
        if isinstance(result, Exception):
            raise result
        yield result.result()
