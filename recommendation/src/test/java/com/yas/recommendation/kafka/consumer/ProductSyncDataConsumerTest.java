package com.yas.recommendation.kafka.consumer;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

import com.yas.commonlibrary.kafka.cdc.message.ProductCdcMessage;
import com.yas.commonlibrary.kafka.cdc.message.ProductMsgKey;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.messaging.MessageHeaders;

import java.util.Map;

class ProductSyncDataConsumerTest {

    @InjectMocks
    private ProductSyncDataConsumer productSyncDataConsumer;

    @Mock
    private ProductSyncService productSyncService;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
    }

    @Test
    void testProcessMessage_shouldExecuteWithoutException() {
        // Given
        ProductMsgKey key = ProductMsgKey.builder().id(1L).build();
        ProductCdcMessage message = ProductCdcMessage.builder()
                .op(com.yas.commonlibrary.kafka.cdc.message.Operation.CREATE)
                .build();
        MessageHeaders headers = new MessageHeaders(Map.of());
        
        // When & Then
        org.junit.jupiter.api.Assertions.assertDoesNotThrow(() -> 
            productSyncDataConsumer.processMessage(key, message, headers)
        );
    }
}
